const handlebars = require("handlebars/dist/handlebars.runtime");
globalThis.Handlebars = handlebars;
require("../build/templates");

module.exports = handlebars;
