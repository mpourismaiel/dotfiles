const [ scope, digit, level ] = process.argv.slice(2)
const fn = {
  year: 'getFullYear',
  month: 'getMonth',
  day: 'getDate',
  hour: 'getHours',
  minute: 'getMinutes',
  second: 'getSeconds',
}
const time = (new Date())[fn[scope.toLowerCase()]]() + (scope.toLowerCase() === 'month' ? 1 : 0).toString()
const str = time.length === 1 ? `0${time}` : time
const num = parseInt(time[parseInt(digit, 10)])
const ret = toLength4(num.toString(2))[level]
if (ret === '1') {
  console.log('${color #fc4384}•')
} else {
  console.log('${color #301f28}•')
}

function toLength4(str) {
  while(str.length < 4) {
    str = `0${str}`
  }
  return str
}
