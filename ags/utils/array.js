export const range = (length, start = 1) =>
  Array.from({ length }, (_, i) => i + start);

export const createRowsOfLength = (arr, length = 1) => {
  const rows = [];
  for (let i = 0; i < arr.length; i += length) {
    rows.push(arr.slice(i, i + length));
  }
  return rows;
};
