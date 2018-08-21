#!/usr/bin/env node

const toPersian = str => {
  const persian = "۱۲۳۴۵۶۷۸۹۰-=ضصثقفغعهخحجچشسیبلاتنمکگظطزرذدپو./!٬٫﷼٪×،*)(ـ+ًٌٍَُِّْ][}{ؤئيإأآة»«:؛كٓژٰ‌ٔء><؟"
  const english = "1234567890-=qwertyuiop[]asdfghjkl;'zxcvbnm,./!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?"
  let tmp = ''
  for (const i of str) {
    tmp += persian[english.indexOf(i || -1)]
  }
  return tmp
}

console.log(toPersian(process.argv[2] || ''))
