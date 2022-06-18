const path = require("path");
const fs = require("fs");
const { sep, resolve } = require("path");

const fa = fs.promises;

const normalizeOptions = ({
  resolve = false,
  isExcludedDir = () => false,
} = {}) => ({ resolve, isExcludedDir });

const normalizeDirname = (dirname, options) => {
  if (options.resolve === true) {
    dirname = resolve(dirname);
  }

  if (dirname.length > 0 && dirname[dirname.length - 1] !== sep) {
    dirname += sep;
  }

  return dirname;
};

function createNotifier() {
  let done = false;
  // eslint-disable-next-line no-empty-function
  let resolve = () => {};
  // eslint-disable-next-line no-empty-function
  let reject = () => {};
  let notified = new Promise((pResolve, pReject) => {
    resolve = pResolve;
    reject = pReject;
  });

  return {
    resolve() {
      const oldResolve = resolve;
      notified = new Promise((pResolve, pReject) => {
        resolve = pResolve;
        reject = pReject;
      });
      oldResolve();
    },
    reject(error) {
      reject(error);
    },
    get done() {
      return done;
    },
    set done(value) {
      done = value;
    },
    onResolved() {
      return notified;
    },
  };
}

function walk(dirnames, filenames, notifier, options) {
  if (dirnames.length === 0) {
    notifier.done = true;
    return;
  }

  const children = [];
  let pending = dirnames.length;

  for (const dirname of dirnames) {
    if (options.isExcludedDir(dirname)) {
      continue;
    }

    // eslint-disable-next-line no-loop-func
    fs.readdir(dirname, { withFileTypes: true }, (error, dirents) => {
      if (error != null) {
        notifier.reject(error);
        return;
      }

      for (const dirent of dirents) {
        const filename = dirname + dirent.name;

        if (dirent.isDirectory()) {
          children.push(filename + sep);
        } else {
          filenames.push(filename);
        }
      }

      notifier.resolve();

      if (--pending === 0) {
        walk(children, filenames, notifier, options);
      }
    });
  }
}

const getAllFiles = (filename, options) => {
  options = normalizeOptions(options);

  const files = {
    async *[Symbol.asyncIterator]() {
      if (!(await fa.lstat(filename)).isDirectory()) {
        yield filename;
        return;
      }

      const filenames = [];
      const notifier = createNotifier();

      walk([normalizeDirname(filename, options)], filenames, notifier, options);

      do {
        await notifier.onResolved();
        while (filenames.length > 0) {
          yield filenames.pop();
        }
      } while (!notifier.done);
    },
    toArray: async (fn) => {
      const filenames = [];

      for await (const filename of files) {
        filenames.push(filename);
      }

      if (fn) {
        fn(filenames);
      }
      return filenames;
    },
  };

  return files;
};

const crawl = async () => {
  const resFile = `${__dirname}/list.json`;

  let previousResults = [];
  if (fs.existsSync(resFile)) {
    const data = fs.readFileSync(resFile, "utf8");
    previousResults = JSON.parse(data);
    if (previousResults.lastChanged + 60000 > Date.now()) {
      return;
    }
  }

  const iconBaseDir1 = "/usr/share/pixmaps";
  const iconBaseDir2 = "/usr/share/app-install/icons";
  const iconDirs = fs
    .readdirSync("/usr/share/icons/")
    .map((name) => {
      const iconPath = path.resolve("/usr/share/icons/", name);
      const stat = fs.statSync(iconPath);
      if (stat && stat.isDirectory()) {
        return iconPath;
      }
      return null;
    })
    .filter((dir) => !!dir);

  const iconThemeRequested = process.argv[3] || "";
  let iconTheme = "";
  if (iconThemeRequested) {
    if (fs.existsSync(`/usr/share/icons/${iconThemeRequested}`)) {
      iconTheme = `/usr/share/icons/${iconThemeRequested}`;
    }
  }

  const iconCache = {};
  const isIcon = (name, path) => {
    let iconPath = (iconCache[path] || []).find((icon) =>
      icon.includes(`${name}.png`)
    );
    if (iconPath) {
      return iconPath;
    }

    iconPath = (iconCache[path] || []).find((icon) =>
      icon.includes(`${name}.svg`)
    );
    if (iconPath) {
      return iconPath;
    }
    return "";
  };

  const findIcon = (name) => {
    if (fs.existsSync(name)) {
      return name;
    }

    if (iconTheme) {
      const path = isIcon(name, iconTheme);
      if (path) {
        return path;
      }
    }

    for (let i = 0; i < iconDirs.length; i++) {
      const path = isIcon(name, iconDirs[i]);
      if (path) {
        return path;
      }
    }

    let path = isIcon(name, iconBaseDir1);
    if (path) {
      return path;
    }

    path = isIcon(name, iconBaseDir2);
    return path;
  };

  new Promise(async (resolve) => {
    const setCache = (path) => (files) => {
      iconCache[path] = files;
    };

    const t1 = Date.now();
    const promises = [];
    if (iconTheme) {
      if (fs.existsSync(iconTheme)) {
        promises.push(getAllFiles(iconTheme).toArray(setCache(iconTheme)));
      }
    }

    for (let i = 0; i < iconDirs.length; i++) {
      if (fs.existsSync(iconDirs[i])) {
        promises.push(getAllFiles(iconDirs[i]).toArray(setCache(iconDirs[i])));
      }
    }

    if (fs.existsSync(iconBaseDir1)) {
      promises.push(getAllFiles(iconBaseDir1).toArray(setCache(iconBaseDir1)));
    }
    if (fs.existsSync(iconBaseDir2)) {
      promises.push(getAllFiles(iconBaseDir2).toArray(setCache(iconBaseDir2)));
    }
    await Promise.all(promises);
    const t2 = Date.now();
    console.log("Found all icons in:", t2 - t1);

    resolve();
  }).then(async () => {
    const files = await getAllFiles("/usr/share/applications").toArray();
    const desktopFiles = files.filter((file) => /\.desktop$/.test(file));

    const results = desktopFiles
      .reduce((tmp, file) => {
        const data = fs.readFileSync(file, "utf8");

        const lines = data.split("\n");

        let iconFilename = (
          lines.find((line) => /^Icon=/.test(line)) || ""
        ).replace(/^Icon=/, "");
        const icon = findIcon(iconFilename);

        let fullName = (
          lines.find((line) => /FullName\.en_/.test(line)) || ""
        ).replace(/FullName.en_.*=/, "");
        let genericName = (
          lines.find((line) => /GenericName\.en_/.test(line)) || ""
        ).replace(/GenericName.en_.*=/, "");
        let normalName = (
          lines.find((line) => /Name=/.test(line)) || ""
        ).replace(/Name=/, "");
        let nameI18n = (
          lines.find((line) => /^\[?Name\[en_/.test(line)) || ""
        ).replace(/Name\[en_.*=/, "");
        let nameBase = (lines.find((line) => /Name/.test(line)) || "").replace(
          /.*Name.*=/,
          ""
        );
        const name =
          fullName || normalName || nameBase || nameI18n || genericName || "";

        const executable = (
          lines.find((line) => /^Exec=/.test(line)) || ""
        ).replace(/^Exec=/, "");
        // executable=$(which $executable_name || echo $executable_name)

        if (!executable) {
          return tmp;
        }

        const prevScore = (
          ((previousResults || {}).list || []).find(
            (f) => f.desktop === file
          ) || { score: 0 }
        ).score;

        tmp.push({ desktop: file, name, executable, icon, score: prevScore });
        return tmp;
      }, [])
      .sort((a, b) => (a.score > b.score ? -1 : 1));

    try {
      fs.rmSync(resFile);
    } catch (err) {}
    fs.writeFileSync(
      resFile,
      JSON.stringify({ list: results, lastChanged: Date.now() }),
      "utf8"
    );
  });
};

const score = async () => {
  const resFile = `${__dirname}/list.json`;
  if (!fs.existsSync(resFile)) {
    await crawl();
  }

  const data = fs.readFileSync(resFile, "utf8");
  const results = JSON.parse(data);
  const app = results.list.find((file) => file.desktop === process.argv[3]);
  app.score++;
  results.list = results.list.sort((a, b) => (a.score > b.score ? -1 : 1));
  fs.writeFileSync(resFile, JSON.stringify(results), "utf8");
};

if (process.argv[2] === "crawl") {
  crawl();
} else {
  score();
}
