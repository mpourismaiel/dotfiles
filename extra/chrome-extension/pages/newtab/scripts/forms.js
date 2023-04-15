const forms = document.querySelectorAll("[data-form]");

const formValues = {};
Array.from(forms || []).forEach((form) => {
  const formName = form.id;

  formValues[formName] = { values: {} };
  form.querySelectorAll("input, textarea, select").forEach((input) => {
    formValues[formName].values[input.name] = input.value;
    input.addEventListener("change", (e) => {
      formValues[formName].values[input.name] = e.target.value;
    });
  });

  const defaultValues = { ...formValues[formName].values };
  formValues[formName].reset = () => {
    formValues[formName].values = { ...defaultValues };
  };
});

const stopPropagation = (fn) => (e) => {
  e.stopPropagation();

  if (fn) {
    fn(e);
  }
};

const preventDefault = (fn) => (e) => {
  e.preventDefault();

  if (fn) {
    fn(e);
  }
};

module.exports = { formValues, stopPropagation, preventDefault };
