const store = require("./store");

const {
  get: getPosition,
  set: setPosition,
  subscribe: subscribePosition,
} = store(0, "weatherPosition");

const {
  get: getWeatherApi,
  set: setWeatherApi,
  subscribe: subscribeWeatherApi,
} = store("", "weatherApi");

const { set: setWeather, subscribe: subscribeWeather } = store(
  { temperature: 0, description: "" },
  "weatherInfo"
);

setTimeout(
  () =>
    navigator.geolocation.getCurrentPosition(function (position) {
      const latitude = position.coords.latitude;
      const longitude = position.coords.longitude;

      setPosition({ latitude, longitude });
    }),
  1000
);

const fetchWeather = () => {
  const cityId = getPosition();
  const apiKey = getWeatherApi();
  if (!cityId || !apiKey) return;

  const apiUrl = `https://api.openweathermap.org/data/2.5/weather?id=${cityId}&appid=${apiKey}&units=metric`;

  fetch(apiUrl)
    .then((response) => response.json())
    .then((data) => {
      // Parse weather data from API response
      const temperature = data.main.temp;
      const description = data.weather[0].description;

      setWeather({ temperature, description });
    })
    .catch((error) => {
      console.error("Error fetching weather data:", error);
    });
};

subscribePosition(fetchWeather);
subscribeWeatherApi(fetchWeather);
fetchWeather();

module.exports = {
  setWeatherApi,
  setPosition,
  subscribeWeather,
};
