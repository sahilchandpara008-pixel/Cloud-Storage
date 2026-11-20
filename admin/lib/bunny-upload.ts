// Browser-only: upload a video straight to Bunny Stream over TUS.
//
// The Bunny API key never reaches the browser: the bunny-stream-create Edge
// Function checks the caller may post in the channel, creates the video and
// hands back a short-lived signature for this one upload.
import { Upload as TusUpload } from "tus-js-client";
import { createClient } from "@/lib/supabase/browser";

// Bunny has no practical size limit; this is only a sanity ceiling.
export const MAX_VIDEO_BYTES = 2 * 1024 * 1024 * 1024; // 2 GB
// A hand-picked thumbnail is a small public image.
export const MAX_THUMBNAIL_BYTES = 5 * 1024 * 1024; // 5 MB

type BunnyAuth = {
  videoId: string;
  libraryId: string;
  authorizationSignature: string;
  authorizationExpire: number;
};

// Videos go up in 32 MB pieces. Sending a 300 MB file as one request meant a
// single dropped connection lost the whole upload ("failed to upload chunk at
// offset 0"); now only the current piece is sent again and the upload goes on
// from where it stopped. Network drops are retried for about 3 minutes.
const CHUNK_BYTES = 32 * 1024 * 1024;
const RETRY_DELAYS = [0, 2000, 5000, 10000, 15000, 30000, 30000, 30000, 60000];

function friendlyTusError(err: Error) {
  const text = err?.message ?? String(err);
  if (/response code: n\/a|ProgressEvent|network/i.test(text)) {
    return new Error(
      "The connection to the video server dropped and didn't come back after several tries. " +
        "Check your internet, then press Try again.",
    );
  }
  return err;
}

function tusUpload(file: File, auth: BunnyAuth, onProgress: (pct: number) => void) {
  return new Promise<void>((resolve, reject) => {
    const upload = new TusUpload(file, {
      endpoint: "https://video.bunnycdn.com/tusupload",
      chunkSize: CHUNK_BYTES,
      retryDelays: RETRY_DELAYS,
      removeFingerprintOnSuccess: true,
      headers: {
        AuthorizationSignature: auth.authorizationSignature,
        AuthorizationExpire: String(auth.authorizationExpire),
        VideoId: auth.videoId,
        LibraryId: auth.libraryId,
      },
      metadata: { filetype: file.type, title: file.name },
      onError: (err) => reject(friendlyTusError(err)),
      onProgress: (sent, total) => onProgress(Math.round((sent / total) * 100)),
      onSuccess: () => resolve(),
    });
    upload.start();
  });
}

// Creates the Bunny video, uploads the file and returns the Bunny video id.
export async function uploadVideoToBunny(
  file: File,
  channelId: string,
  onProgress: (pct: number) => void,
): Promise<string> {
  const supabase = createClient();
  const { data: auth, error } = await supabase.functions.invoke("bunny-stream-create", {
    body: { title: file.name, channel_id: channelId },
  });
  if (error) throw error;
  if (auth?.error) throw new Error(auth.error);
  await tusUpload(file, auth as BunnyAuth, onProgress);
  return (auth as BunnyAuth).videoId;
}
