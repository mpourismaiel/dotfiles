#!/usr/bin/env node
// nmcli connection show
process.stdin.resume();
process.stdin.setEncoding('utf-8');

let inputString = '';
let rawConnections = [];

process.stdin.on('data', inputStdin => {
  inputString += inputStdin;
});

process.stdin.on('end', _ => {
  rawConnections = inputString
    .trim()
    .split('\n')
    .map(string => {
      return string.trim();
    });

  main();
});

const main = () => {
  const connections = rawConnections
    .map(connection => {
      let tmp = connection;
      const device = tmp.slice(tmp.lastIndexOf(' ') + 1);
      tmp = tmp.slice(0, tmp.length - device.length).trim();
      const type = tmp.slice(tmp.lastIndexOf(' ') + 1);
      tmp = tmp.slice(0, tmp.length - type.length).trim();
      const uuid = tmp.slice(tmp.lastIndexOf(' ') + 1);
      const name = tmp.slice(0, tmp.length - uuid.length).trim();
      return { name, uuid, type, connected: device !== '--' };
    })
    .reduce((tmp, connection, i) => {
      if (i === 0 || connection.type !== 'vpn') {
        return tmp;
      }

      tmp.push(connection);
      return tmp;
    }, [])
    .sort((a, b) =>
      a.connected && !b.connected ? -1 : !a.connected && b.connected ? 1 : 0,
    );

  console.log(JSON.stringify(connections));
};
