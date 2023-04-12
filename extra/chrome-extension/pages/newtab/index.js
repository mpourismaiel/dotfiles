require("./shortcuts");
require("./bookmarks");
require("./add-shortcuts");
require("./tabs");
require("./search");

const timeState = document.querySelector("#greeting #time-state");
const date = document.querySelector("#greeting #greeting-info #date");
const time = document.querySelector("#greeting #greeting-info #time");
const weather = document.querySelector("#greeting #greeting-info #weather");

const timeMessages = {
  "19-24": "Good night!",
  "24-3": "Nice night, isn't it?",
  "3-8": "You should be sleeping...",
  "8-12": "Good morning!",
  "12-15": "Lunch time!",
  "15-19": "Nice Evening",
};

const timeStates = Object.keys(timeMessages)
  .map((timeRange) => {
    let [start, end] = timeRange.split("-").map((d) => parseInt(d));
    start = start === 24 ? 0 : start;
    const arr = [];
    for (let i = start + 1; i <= end; i++) {
      arr.push(i === 24 ? 0 : i);
    }

    return [timeMessages[timeRange], arr];
  })
  .reduce((tmp, [message, hours]) => {
    hours.forEach((hour) => (tmp[hour] = message));
    return tmp;
  }, {});

const setTimeState = () => {
  const date = new Date();
  const hour = date.getHours();

  timeState.innerText = timeStates[hour];
};
setTimeState();
setInterval(setTimeState, 60000);

const dateMap = {
  1: "1st",
  2: "2nd",
  3: "3rd",
};
const setDate = () => {
  const d = new Date();
  date.innerHTML = d
    .toLocaleDateString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
    })
    .replace(/,\s\d+$/, "")
    .replace(/(\d+)$/, (substr) => {
      const ret = substr.padStart(2, "0");
      return (ret[0] + (dateMap[ret[1]] || ret[1] + "th")).replace(/^0/, "");
    });
};

const setTime = () => {
  const d = new Date();
  const hours = d.getHours().toString().padStart(2, "0");
  const minutes = d.getMinutes().toString().padStart(2, "0");
  time.innerHTML = `${hours}:${minutes}`;
};

setDate();
setTime();
setInterval(() => {
  setDate();
  setTime();
}, 1000);
