npm_publish() {
  yarn build
  git commit -am $1
  git push
  npm publish
}
