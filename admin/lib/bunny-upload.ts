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

function tusUpload(file: File, auth: BunnyAuth, onProgress: (pct: number) => void) {
  return new Promise<void>((resolve, reject) => {
    const upload = new TusUpload(file, {
      endpoint: "https://video.bunnycdn.com/tusupload",
      retryDelays: [0, 1000, 3000, 5000],
      headers: {
        AuthorizationSignature: auth.authorizationSignature,
        AuthorizationExpire: String(auth.authorizationExpire),
        VideoId: auth.videoId,
        LibraryId: auth.libraryId,
      },
      metadata: { filetype: file.type, title: file.name },
      onError: reject,
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
