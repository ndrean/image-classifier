defmodule App.Image do
  use Ecto.Schema

  @moduledoc """
  Ecto schema for the table Images and
  utility functions.
  """

  @primary_key {:id, :id, autogenerate: true}
  schema "images" do
    field(:description, :string)
    field(:width, :integer)
    field(:url, :string)
    field(:height, :integer)
    field(:idx, :integer)
    field(:sha1, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(image, params \\ %{}) do
    image
    |> Ecto.Changeset.cast(params, [:url, :description, :width, :height, :idx, :sha1])
    |> Ecto.Changeset.validate_required([:width, :height])
    |> Ecto.Changeset.unique_constraint(:sha1, name: :images_sha1_index)
    |> Ecto.Changeset.unique_constraint(:idx, name: :images_idx_index)
  end

  def insert(params) do
    App.Image.changeset(%App.Image{}, params)
    |> App.Repo.insert()
  end

  @doc """
  Uploads the given image to S3
  and adds the image information to the database.
  """

  # def insert(image_info) do
  #   image = Map.take(image_info, [:mimetype, :width, :height, :url, :description, :sha1])
  #   changeset = changeset(%Image{}, image)

  #   case changeset.valid? do
  #     true -> Repo.insert(changeset)
  #     false -> {:error, changeset.errors}
  #   end
  # end

  # def update(sha1, %AppWeb.PageLive.ImageInfo{} = params) do
  #   image =
  #     App.Repo.get_by(App.Image, sha1: sha1)

  #   params = Map.take(params, [:mimetype, :width, :height, :url, :description, :sha1])

  #   changeset =
  #     changeset(image, params)

  #   require Logger

  #   case changeset.valid? do
  #     true ->
  #       Logger.info(image)
  #       {:ok, _img} = App.Repo.update(image, changeset)

  #     false ->
  #       {:error, inspect(changeset.errors)}
  #   end
  # end

  def check_before_append_to_index(sha1) do
    App.Repo.get_by(App.Image, sha1: sha1)
    |> case do
      %App.Image{} = img ->
        {:ok, img}

      res ->
        require Logger
        Logger.warning(inspect(res))
        {:error, "Already uploaded"}
    end
  end

  @doc """
  Calculates the SHA1 of a given binary
  """
  def calc_sha1(file_binary) do
    :crypto.hash(:sha, file_binary)
    |> Base.encode16()
  end

  @doc """
  Returns `:ok` or `nil` if the given sha1 is saved into the database Image table.
  """
  def check_sha1(sha1) do
    App.Repo.get_by(App.Image, %{sha1: sha1})
    |> case do
      nil ->
        :ok

      %App.Image{} = image ->
        image
    end
  end

  @doc """
  Uploads the given image to S3.
  Returns {:ok, response} if the upload is successful.
  Returns {:error, reason} if the upload fails.
  """
  def upload_image_to_s3(file_path, mimetype) do
    extension = MIME.extensions(mimetype) |> Enum.at(0)

    # Upload to Imgup - https://github.com/dwyl/imgup
    upload_response =
      HTTPoison.post(
        "https://imgup.fly.dev/api/images",
        {:multipart,
         [
           {
             :file,
             file_path,
             {"form-data", [name: "image", filename: "#{Path.basename(file_path)}.#{extension}"]},
             [{"Content-Type", mimetype}]
           }
         ]},
        []
      )

    # Process the response and return error if there was a problem uploading the image
    case upload_response do
      # In case it's successful
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        %{"url" => url, "compressed_url" => _} = Jason.decode!(body)
        {:ok, url}

      # In case it returns HTTP 400 with specific reason it failed
      {:ok, %HTTPoison.Response{status_code: 400, body: body}} ->
        %{"errors" => %{"detail" => reason}} = Jason.decode!(body)
        {:error, reason}

      # In case the request fails for whatever other reason
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  @doc """
  Check file type via magic number. It uses a GenServer running the `C` lib "libmagic".
  Returns {:ok, %{mime_type: mime_type}} if the file type is accepted.
  Otherwise, {:error, reason}.
  """
  def gen_magic_eval(path, accepted_mime) do
    GenMagic.Server.perform(:gen_magic, path)
    |> case do
      {:error, reason} ->
        {:error, reason}

      {:ok,
       %GenMagic.Result{
         mime_type: mime,
         encoding: "binary",
         content: _content
       }} ->
        if Enum.member?(accepted_mime, mime),
          do: {:ok, %{mime_type: mime}},
          else: {:error, "Not accepted mime type."}

      {:ok, %GenMagic.Result{} = res} ->
        require Logger
        Logger.warning(%{gen_magic_response: res})
        {:error, "Not acceptable."}
    end
  end
end
