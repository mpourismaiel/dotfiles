const store = (initial = {}, key) => {
  const subscribers = [];
  let data = initial;

  if (key) {
    const memory = localStorage.getItem(key);
    try {
      data = JSON.parse(memory);
      if (!data) {
        throw new Error();
      }
    } catch (err) {
      data = initial;
      localStorage.setItem(key, JSON.stringify(data));
    }
  }

  const emit = () => {
    subscribers.forEach((fn) => fn(data));
  };

  const set = (newData) => {
    data = newData;
    if (key) {
      localStorage.setItem(key, JSON.stringify(data));
    }
    emit();
  };

  const get = () => {
    return data;
  };

  const subscribe = (fn) => {
    subscribers.push(fn);
    fn(data);
  };

  return { set, get, subscribe };
};

module.exports = store;
