defmodule AppWeb.PageLive do
  use AppWeb, :live_view
  alias Vix.Vips.Image, as: Vimage

  @unsplashes [
    "https://source.unsplash.com/_CFv3bntQlQ",
    "https://source.unsplash.com/r1SwcagHVG0"
  ]

  @impl true
  def mount(_params, _session, socket) do
    Process.send_after(self(), :example_list, 3_000)

    {:ok,
     socket
     |> assign(
       label: nil,
       running: false,
       task_ref: nil,
       image_preview_base64: nil,
       display_list?: false,
       displayed_list: []
     )
     |> allow_upload(:image_list,
       accept: ~w(image/*),
       auto_upload: true,
       progress: &handle_progress/3,
       max_entries: 1,
       chunk_size: 64_000,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_progress(:image_list, entry, socket) do
    if entry.done? do
      # Consume the entry and get the tensor to feed to classifier
      %{tensor: tensor, file_binary: file_binary} =
        consume_uploaded_entry(socket, entry, fn %{} = meta ->
          file_binary = File.read!(meta.path)

          # Get image and resize
          # This is dependant on the resolution of the model's dataset.
          # In our case, we want the width to be closer to 640, whilst maintaining aspect ratio.
          width = 640

          {:ok, thumbnail_vimage} =
            Vix.Vips.Operation.thumbnail(meta.path, width, size: :VIPS_SIZE_DOWN)

          # Pre-process it
          {:ok, tensor} = pre_process_image(thumbnail_vimage)

          # Return it
          {:ok, %{tensor: tensor, file_binary: file_binary}}
        end)

      # Create an async task to classify the image
      task =
        Task.Supervisor.async(App.TaskSupervisor, fn ->
          Nx.Serving.batched_run(ImageClassifier, tensor)
        end)

      # Encode the image to base64
      base64 = "data:image/png;base64, " <> Base.encode64(file_binary)

      # Update socket assigns to show spinner whilst task is running
      {:noreply, assign(socket, running: true, task_ref: task.ref, image_preview_base64: base64)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({ref, result}, %{assigns: assigns} = socket) do
    # This is called everytime an Async Task is created.
    # We flush it here.
    Process.demonitor(ref, [:flush])

    # You need to change how you destructure the output of the model depending
    # on the model you've chosen for `prod` and `test` envs on `models.ex`.)
    label =
      case Application.get_env(:app, :use_test_models, false) do
        true ->
          App.Models.extract_test_label(result)

        # coveralls-ignore-start
        false ->
          App.Models.extract_prod_label(result)
        # coveralls-ignore-stop
      end

    cond do
      Map.get(assigns, :task_ref) == ref ->
        {:noreply, assign(socket, label: label, running: false)}

      img = Map.get(assigns, :example_list_tasks) |> Enum.find(&(&1.ref == ref)) ->
        {:noreply,
         assign(socket,
           displayed_list: [%{url: img.url, label: label} | assigns.displayed_list],
           running: false,
           display_list?: true
         )}
    end
  end

  def handle_info(:example_list, socket) do
    tasks = @unsplashes |> Enum.map(&handle_image/1)

    {:noreply, assign(socket, example_list_tasks: tasks)}
  end

  @doc """
  This function fetches a public image from the Unsplash website with the Req library.
  Vix is used to produce an optimized thumbnail of size 640 to match the COCO dataset
  used to train the BLIP model.
  """
  def handle_image(url) do
    with {:req, body} <- {:req, Req.get!(url).body},
         {:vix, {:ok, img_thumb}} <-
           {:vix, Vix.Vips.Operation.thumbnail_buffer(body, 640)},
         {:pre_process, {:ok, t_img}} <- {:pre_process, pre_process_image(img_thumb)} do
      Task.Supervisor.async(App.TaskSupervisor, fn ->
        Nx.Serving.batched_run(ImageClassifier, t_img)
      end)
      |> Map.merge(%{url: url})
    else
      {stage, error} -> {stage, error}
    end
  end

  def error_to_string(:too_large), do: "Image too large. Upload a smaller image up to 10MB."

  defp pre_process_image(%Vimage{} = image) do
    # If the image has an alpha channel, flatten it:
    {:ok, flattened_image} =
      case Vix.Vips.Image.has_alpha?(image) do
        true -> Vix.Vips.Operation.flatten(image)
        false -> {:ok, image}
      end

    # Convert the image to sRGB colourspace ----------------
    {:ok, srgb_image} = Vix.Vips.Operation.colourspace(flattened_image, :VIPS_INTERPRETATION_sRGB)

    # Converting image to tensor ----------------
    {:ok, tensor} = Vix.Vips.Image.write_to_tensor(srgb_image)

    # We reshape the tensor given a specific format.
    # In this case, we are using {height, width, channels/bands}.
    %Vix.Tensor{data: binary, type: type, shape: {x, y, bands}} = tensor
    format = [:height, :width, :bands]
    shape = {x, y, bands}

    final_tensor =
      binary
      |> Nx.from_binary(type)
      |> Nx.reshape(shape, names: format)

    {:ok, final_tensor}
  end
end
