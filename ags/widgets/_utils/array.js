export const range = (length, start = 1) =>
  Array.from({ length }, (_, i) => i + start);
