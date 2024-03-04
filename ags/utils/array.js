export const range = (length, start = 1) =>
  Array.from({ length }, (_, i) => i + start);

export const createRowsOfLength = (arr, length = 1) => {
  const rows = [];
  for (let i = 0; i < arr.length; i += length) {
    rows.push(arr.slice(i, i + length));
  }
  return rows;
};

export const arrAdd = (arr, value) => {
  if (arr.includes(value)) return arr;

  arr.push(value);
  return arr;
};

export const arrRemove = (arr, value) => {
  const index = arr.indexOf(value);
  if (index > -1) {
    arr.splice(index, 1);
  }
  return arr;
};
