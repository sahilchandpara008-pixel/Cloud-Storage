// Browser-only helpers: read video/image size and make a JPEG thumbnail.

export const MAX_UPLOAD_BYTES = 50 * 1024 * 1024; // Supabase free plan limit
const THUMB_WIDTH = 480;

export type MediaInfo = {
  kind: "video" | "image";
  width: number;
  height: number;
  durationS: number | null;
  thumbnail: Blob;
};

function canvasToJpeg(
  source: CanvasImageSource,
  width: number,
  height: number,
  maxWidth = THUMB_WIDTH,
): Promise<Blob> {
  const scale = Math.min(1, maxWidth / width);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  canvas.getContext("2d")!.drawImage(source, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("thumbnail failed"))), "image/jpeg", 0.8),
  );
}

function readImage(file: File): Promise<MediaInfo> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = async () => {
      try {
        const thumbnail = await canvasToJpeg(img, img.naturalWidth, img.naturalHeight);
        resolve({ kind: "image", width: img.naturalWidth, height: img.naturalHeight, durationS: null, thumbnail });
      } catch (e) {
        reject(e);
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    img.onerror = () => reject(new Error(`Can't read image ${file.name}`));
    img.src = url;
  });
}

function readVideo(file: File): Promise<MediaInfo> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement("video");
    video.preload = "auto";
    video.muted = true;
    video.playsInline = true;
    video.onloadedmetadata = () => {
      // Grab a frame a little way in (avoids black first frames).
      video.currentTime = Math.min(1, (video.duration || 0) / 3);
    };
    video.onseeked = async () => {
      try {
        const thumbnail = await canvasToJpeg(video, video.videoWidth, video.videoHeight);
        resolve({
          kind: "video",
          width: video.videoWidth,
          height: video.videoHeight,
          durationS: Number.isFinite(video.duration) ? Math.round(video.duration) : null,
          thumbnail,
        });
      } catch (e) {
        reject(e);
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    video.onerror = () => reject(new Error(`Can't read video ${file.name} (use MP4/H.264)`));
    video.src = url;
  });
}

export function readMedia(file: File): Promise<MediaInfo> {
  if (file.type.startsWith("video/")) return readVideo(file);
  if (file.type.startsWith("image/")) return readImage(file);
  return Promise.reject(new Error(`${file.name} is not a video or image`));
}

// A hand-picked thumbnail: any picture the browser can open, re-encoded as a
// JPEG no wider than [maxWidth] (bigger than the auto frame, since it's the
// cover people see first).
export function toJpegThumbnail(file: File, maxWidth = 960): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = async () => {
      try {
        resolve(await canvasToJpeg(img, img.naturalWidth, img.naturalHeight, maxWidth));
      } catch (e) {
        reject(e);
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error(`Can't read thumbnail ${file.name}`));
    };
    img.src = url;
  });
}

export function extension(file: File) {
  const fromName = file.name.includes(".") ? file.name.split(".").pop()!.toLowerCase() : "";
  return fromName || file.type.split("/")[1] || "bin";
}

export function formatBytes(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export type PreparedThumbnail = { blob: Blob; contentType: string; ext: string };

// What kind of picture the bytes really are (the file name and the browser's
// guess can be wrong: covers saved from websites are often WebP or AVIF with
// a .jpg name).
async function sniffImage(file: File): Promise<{ contentType: string; ext: string } | null> {
  const b = new Uint8Array(await file.slice(0, 16).arrayBuffer());
  const ascii = (from: number, to: number) => String.fromCharCode(...b.slice(from, to));
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { contentType: "image/jpeg", ext: "jpg" };
  if (b[0] === 0x89 && ascii(1, 4) === "PNG") return { contentType: "image/png", ext: "png" };
  if (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return { contentType: "image/webp", ext: "webp" };
  if (ascii(0, 3) === "GIF") return { contentType: "image/gif", ext: "gif" };
  return null;
}

// A hand-picked thumbnail, made as dependable as possible:
//   1. decode it (createImageBitmap, then <img>) and re-encode as JPEG;
//   2. if this browser can't decode it but the bytes are a normal JPEG / PNG /
//      WebP / GIF, use the file exactly as it is;
//   3. otherwise give up (the caller falls back to a frame from the video).
export async function prepareThumbnail(file: File, maxWidth = 960): Promise<PreparedThumbnail> {
  try {
    const bitmap = await createImageBitmap(file);
    try {
      const blob = await canvasToJpeg(bitmap, bitmap.width, bitmap.height, maxWidth);
      return { blob, contentType: "image/jpeg", ext: "jpg" };
    } finally {
      bitmap.close();
    }
  } catch {
    // try the next way
  }
  try {
    return { blob: await toJpegThumbnail(file, maxWidth), contentType: "image/jpeg", ext: "jpg" };
  } catch {
    // try the next way
  }
  const kind = await sniffImage(file);
  if (kind) return { blob: file, ...kind };
  throw new Error(`Can't open the picture ${file.name}. Save it again as JPG or PNG and pick it again.`);
}
