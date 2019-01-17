const fn = [
  'getFullYear',
  'getMonth',
  'getDate',
  'getHours',
  'getMinutes',
  'getSeconds',
]
let time = ''
let ret = ''
const mem = {}

for (let i = 0; i < fn.length; i++) {
  time += toLength(((new Date())[fn[i]]() + (fn[i] === 'getMonth' ? 1 : 0)).toString(), 2) + ' '
}

time = time.trim()

for (let j = 0; j < 4; j++) {
  for (let i = 0; i < time.length; i++) {
    if (time[i] === ' ') {
      ret += '  '
      continue
    }
    if (mem[i] === undefined) {
      mem[i] = toLength(parseInt(time[i]).toString(2), 4)
    }
    ret += (mem[i][j] === '1' ? '${color #fc4384}•' : '${color #301f28}•') + ' '
  }
  ret = ret.trim() + '\n'
}

ret += '${color #fc4384}'
for (let i = 0; i < time.length; i++) {
  ret += time[i] + ' '
}

console.log(ret)

function toLength(str, length) {
  while(str.length < length) {
    str = `0${str}`
  }
  return str
}
