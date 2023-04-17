const formValues = {};

const setupForms = (scope) => {
  const forms = scope.querySelectorAll("[data-form]");
  Array.from(forms || []).forEach((form) => {
    const formName = form.id;

    formValues[formName] = { values: {} };
    Array.from(form.querySelectorAll("input, textarea, select")).forEach(
      (input) => {
        formValues[formName].values[input.name] = input.value;
        input.addEventListener("change", (e) => {
          formValues[formName].values[input.name] = e.target.value;
        });
      }
    );

    const defaultValues = { ...formValues[formName].values };
    formValues[formName].reset = () => {
      formValues[formName].values = { ...defaultValues };
    };
  });
};

const removeForms = (scope) => {
  const forms = scope.querySelectorAll("[data-form]");
  Array.from(forms || []).forEach((form) => {
    const formName = form.id;

    delete formValues[formName];
  });
};

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

setupForms(document);

module.exports = {
  formValues,
  stopPropagation,
  preventDefault,
  setupForms,
  removeForms,
};
