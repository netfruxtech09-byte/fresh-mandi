import path from 'path';

export function getUploadsDir(appDirname) {
  if (process.env.UPLOADS_DIR?.trim()) {
    return process.env.UPLOADS_DIR.trim();
  }

  if (process.env.VERCEL) {
    return '/tmp/uploads';
  }

  return path.resolve(appDirname, '../public/uploads');
}
