const AudioTypeIconSubstitudes = {
  "audio-headset-bluetooth": "audio-headphones-symbolic",
  "audio-card-analog-usb": "audio-speakers-symbolic",
  "audio-card-analog-pci": "audio-card-symbolic",
};

export function getAudioTypeIcon(icon) {
  if (icon in AudioTypeIconSubstitudes) {
    return AudioTypeIconSubstitudes[icon];
  }

  return icon;
}

export function substitudeClientClass(clientClass) {
  if (clientClass in ClientClassSubstitudes) {
    return ClientClassSubstitudes[clientClass];
  }

  return clientClass;
}

const ClientClassSubstitudes = {
  "code-insiders-url-handler": "code",
  "xfce4-terminal": "terminal",
};

const ClientPossibleIcons = [
  (cls) => (Utils.lookUpIcon(cls) ? cls : null),
  (cls) =>
    Utils.lookUpIcon(substitudeClientClass(cls))
      ? substitudeClientClass(cls)
      : null,
];

export function lookupIcon(clientClass) {
  for (const icon of ClientPossibleIcons) {
    const cls = icon(clientClass);
    if (cls) {
      return cls;
    }
  }

  return "application-x-executable";
}
