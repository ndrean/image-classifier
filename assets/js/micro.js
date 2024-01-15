export default {
  mounted() {
    let mediaRecorder,
      audioChunks = [];
    const recordButton = document.getElementById("record"),
      audioElement = document.getElementById("audio"),
      text = document.getElementById("text"),
      blue = ["bg-blue-500", "hover:bg-blue-700"],
      pulseGreen = ["bg-green-500", "hover:bg-green-700", "animate-pulse"];

    _this = this;

    recordButton.addEventListener("click", () => {
      if (mediaRecorder && mediaRecorder.state === "recording") {
        mediaRecorder.stop();
        text.textContent = "Record";
      } else {
        navigator.mediaDevices.getUserMedia({ audio: true }).then((stream) => {
          mediaRecorder = new MediaRecorder(stream);
          mediaRecorder.start();
          recordButton.classList.remove(...blue);
          recordButton.classList.add(...pulseGreen);
          text.textContent = "Stop";

          mediaRecorder.addEventListener("dataavailable", (event) =>
            audioChunks.push(event.data)
          );

          mediaRecorder.addEventListener("stop", () => {
            const audioBlob = new Blob(audioChunks);
            audioElement.src = URL.createObjectURL(audioBlob);

            _this.upload("speech", [audioBlob]);
            audioChunks = [];
            recordButton.classList.remove(...pulseGreen);
            recordButton.classList.add(...blue);
          });
        });
      }
    });
  },
};
