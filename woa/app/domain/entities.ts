// app/domain/entities.ts
export function mapFilenameToGroup(filename: string): string {
  const segments = filename.split('/');
  return segments.join('_');
}
