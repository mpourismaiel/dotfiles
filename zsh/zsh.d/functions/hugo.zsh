hugo_install() {
    tmpd
    aria2c $1
    tar -xzf ./$(echo $1 | sed 's/^.*hugo_extended/hugo_extended/')
    cp ~/go/bin/hugo ~/.bcp/hugo-$(hugo version | awk '{print $5}' | sed 's/\/.*$//')
    mv hugo ~/go/bin/hugo
}
