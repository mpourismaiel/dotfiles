const modalBackdrop = document.querySelector("#backdrop");

const showModal = (modal) => () => {
  modalBackdrop.classList.remove("hide");
  modal.classList.remove("hide");
  modalBackdrop.addEventListener("click", hideModal(modal), { once: true });
};

const hideModal = (modal) => () => {
  modalBackdrop.classList.add("hide");
  modal.classList.add("hide");
};

module.exports = { showModal, hideModal };
