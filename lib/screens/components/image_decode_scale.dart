/// Ignore tiny zoom adjustments and decode only at a few stable resolutions.
/// Keep the current tier while viewing the same page to avoid decode thrashing.
double imageDecodeScale(double zoom) {
  if (!zoom.isFinite || zoom <= 1.25) return 1;
  if (zoom <= 2) return 2;
  if (zoom <= 3) return 3;
  return 4;
}
