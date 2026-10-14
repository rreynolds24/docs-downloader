// Fortinet Docs Downloader corpus layout migration.
// Windows Script Host only; no PowerShell/Python dependency.
// Usage: cscript //nologo scripts\corpus-layout.js migrate <runtime-dir>

(function () {
  var args = WScript.Arguments;
  if (args.length < 2 || String(args.Item(0)).toLowerCase() !== "migrate") {
    WScript.Echo("Usage: corpus-layout.js migrate <runtime-dir>");
    WScript.Quit(2);
  }

  var fso = new ActiveXObject("Scripting.FileSystemObject");
  var runtime = fso.GetAbsolutePathName(args.Item(1));
  var downloads = fso.BuildPath(runtime, "downloads");
  var state = fso.BuildPath(runtime, "state");
  var catalogue = fso.BuildPath(state, "catalogue.db");
  var manifest = fso.BuildPath(state, "downloads.db");
  var sources = fso.BuildPath(state, "sources.db");
  var work = fso.BuildPath(runtime, "temp");
  var txn = fso.BuildPath(work, "layout-v2-migration");

  function ensureDir(path) {
    if (fso.FolderExists(path)) return;
    var parent = fso.GetParentFolderName(path);
    if (parent && !fso.FolderExists(parent)) ensureDir(parent);
    fso.CreateFolder(path);
  }

  function readLines(path) {
    var out = [];
    if (!fso.FileExists(path)) return out;
    var h = fso.OpenTextFile(path, 1, false, -2);
    while (!h.AtEndOfStream) out.push(h.ReadLine());
    h.Close();
    return out;
  }

  function writeLines(path, lines) {
    var h = fso.CreateTextFile(path, true, false);
    for (var i = 0; i < lines.length; i++) h.WriteLine(lines[i]);
    h.Close();
  }

  function safePart(value, fallback) {
    var s = String(value || "");
    if (!s || s === "-" || s.toLowerCase() === "unknown") s = fallback;
    s = s.replace(/[<>:"\/\\|?*]/g, "_").replace(/[. ]+$/g, "");
    return s || fallback;
  }

  function normRel(value) {
    return String(value || "").replace(/\//g, "\\");
  }

  function isNested(value) {
    value = normRel(value);
    return value.indexOf("\\") >= 0;
  }

  function destinationFor(row, filename) {
    var product = String(row[1] || "unknown");
    var sourceVersion = String(row[3] || "unknown");
    var documentVersion = String(row[4] || "unknown");
    var catalogueUrl = String(row[14] || "");
    var name = safePart(filename, "document.pdf");

    if (catalogueUrl.toLowerCase().indexOf("https://docs.fortinet.com/ordering-guides") === 0 ||
        product.toLowerCase() === "solution-ordering-guides") {
      return "ordering-guides\\" + name;
    }

    if (product.toLowerCase().indexOf("solution-") === 0) {
      var solution = safePart(product.substring(9), "unknown");
      var sv = safePart(sourceVersion, "latest");
      return "solution-hubs\\" + solution + "\\" + sv + "\\" + name;
    }

    var prod = safePart(product, "unknown");
    var ver = documentVersion;
    if (!ver || ver === "-" || ver.toLowerCase() === "unknown") ver = sourceVersion;
    ver = safePart(ver, "unknown");
    return "products\\" + prod + "\\" + ver + "\\" + name;
  }

  function priority(row) {
    var product = String(row[1] || "").toLowerCase();
    var catalogueUrl = String(row[14] || "").toLowerCase();
    if (product.indexOf("solution-") !== 0) return 30;
    if (catalogueUrl.indexOf("https://docs.fortinet.com/ordering-guides") === 0 ||
        product === "solution-ordering-guides") return 20;
    return 10;
  }

  ensureDir(downloads);
  ensureDir(state);
  ensureDir(work);
  if (fso.FolderExists(txn)) {
    WScript.Echo("[FAIL] Prior transaction directory remains; manual recovery required: " + txn);
    WScript.Quit(7);
  }
  ensureDir(txn);

  var rows = readLines(catalogue);
  var choices = {};
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i]) continue;
    var fields = rows[i].split("|");
    if (fields.length < 15) continue;
    var local = normRel(fields[12]);
    if (!local || local === "-" || isNested(local)) continue;
    var key = local.toLowerCase();
    var candidate = { row: fields, score: priority(fields), dest: destinationFor(fields, local) };
    if (!choices[key] || candidate.score > choices[key].score) choices[key] = candidate;
  }


  // Recover filename hints from historical acquisition rows.
  var hints = {};
  function hint(name, url) {
    if (!name || isNested(name) || name === "-") return;
    var match = String(url).match(/^https:\/\/docs\.fortinet\.com\/document\/([^\/]+)\/([^\/]+)\//i);
    if (!match) return;
    var key = name.toLowerCase();
    var dst = "products\\" + safePart(match[1], "unknown") + "\\" + safePart(match[2], "unknown") + "\\" + name;
    if (Object.prototype.hasOwnProperty.call(hints, key) && hints[key] !== dst) hints[key] = null;
    else if (!Object.prototype.hasOwnProperty.call(hints, key)) hints[key] = dst;
  }
  var legacyManifest = readLines(manifest);
  for (var k = 0; k < legacyManifest.length; k++) {
    var mr = legacyManifest[k].split("|");
    if (mr.length >= 5) hint(mr[4], mr[0]);
  }
  var legacySources = readLines(sources);
  for (var s = 0; s < legacySources.length; s++) {
    var sr = legacySources[s].split("|");
    if (sr.length >= 7) hint(sr[6], sr[1]);
  }

  var mapping = {};
  var mappingCount = 0;
  var planned = [];
  for (var key in choices) {
    if (!choices.hasOwnProperty(key)) continue;
    var oldRel = normRel(choices[key].row[12]);
    var newRel = normRel(choices[key].dest);
    var src = fso.BuildPath(downloads, oldRel);
    var dst = fso.BuildPath(downloads, newRel);

    if (!fso.FileExists(src)) {
      if (fso.FileExists(dst)) {
        mapping[key] = newRel;
        mappingCount++;
        continue;
      }
      WScript.Echo("[WARN] Catalogue file is not present locally; leaving reference unchanged: " + oldRel);
      continue;
    }

    if (fso.FileExists(dst) && src.toLowerCase() !== dst.toLowerCase()) {
      WScript.Echo("[FAIL] Migration destination already exists: " + newRel);
      WScript.Quit(5);
    }

    mapping[key] = newRel;
    mappingCount++;
    if (src.toLowerCase() !== dst.toLowerCase()) planned.push({ oldRel: oldRel, newRel: newRel, src: src, dst: dst });
  }


  // Migrate every remaining root PDF even when it has no eligible catalogue row.
  var rootFiles = new Enumerator(fso.GetFolder(downloads).Files);
  var unclassified = 0;
  for (; !rootFiles.atEnd(); rootFiles.moveNext()) {
    var rootFile = rootFiles.item();
    if (!/\.pdf$/i.test(rootFile.Name)) continue;
    var rootKey = rootFile.Name.toLowerCase();
    if (mapping[rootKey]) continue;
    var dstRel = hints[rootKey] || ("unclassified\\" + rootFile.Name);
    var dstPath = fso.BuildPath(downloads, dstRel);
    if (fso.FileExists(dstPath)) {
      WScript.Echo("[FAIL] Existing destination collision: " + dstRel);
      WScript.Quit(5);
    }
    if (!hints[rootKey]) unclassified++;
    mapping[rootKey] = dstRel;
    mappingCount++;
    planned.push({ oldRel: rootFile.Name, newRel: dstRel, src: rootFile.Path, dst: dstPath });
  }

  function rewrite(path, fieldIndex, tempName) {
    var input = readLines(path);
    var output = [];
    for (var n = 0; n < input.length; n++) {
      var line = input[n];
      if (!line) { output.push(line); continue; }
      var f = line.split("|");
      if (f.length > fieldIndex) {
        var current = normRel(f[fieldIndex]);
        var mapped = mapping[current.toLowerCase()];
        if (mapped) f[fieldIndex] = mapped;
      }
      output.push(f.join("|"));
    }
    var tempPath = fso.BuildPath(txn, tempName);
    writeLines(tempPath, output);
    return tempPath;
  }

  var catNew = rewrite(catalogue, 12, "catalogue.db.new");
  var manNew = rewrite(manifest, 4, "downloads.db.new");
  var srcNew = rewrite(sources, 6, "sources.db.new");
  var moved = [];

  try {
    for (var p = 0; p < planned.length; p++) {
      ensureDir(fso.GetParentFolderName(planned[p].dst));
      fso.MoveFile(planned[p].src, planned[p].dst);
      moved.push(planned[p]);
    }

    var dbs = [
      { live: catalogue, fresh: catNew, backup: fso.BuildPath(txn, "catalogue.db.bak") },
      { live: manifest, fresh: manNew, backup: fso.BuildPath(txn, "downloads.db.bak") },
      { live: sources, fresh: srcNew, backup: fso.BuildPath(txn, "sources.db.bak") }
    ];

    for (var d = 0; d < dbs.length; d++) {
      if (fso.FileExists(dbs[d].live)) fso.CopyFile(dbs[d].live, dbs[d].backup, true);
      fso.CopyFile(dbs[d].fresh, dbs[d].live, true);
    }

    writeLines(fso.BuildPath(state, "corpus-layout-v2.ok"), [
      "layout=2",
      "moved=" + moved.length,
      "updated_references=" + mappingCount
    ]);

    WScript.Echo("[PASS] Corpus layout migration complete.");
    WScript.Echo("       Files moved          : " + moved.length);
    WScript.Echo("       References updated   : " + mappingCount);
    WScript.Echo("       Unclassified PDFs    : " + unclassified);
    WScript.Echo("       Download root        : " + downloads);
    fso.DeleteFolder(txn, true);
    WScript.Quit(0);
  } catch (e) {
    WScript.Echo("[FAIL] Corpus layout migration failed: " + e.message);

    for (var r = moved.length - 1; r >= 0; r--) {
      try {
        if (fso.FileExists(moved[r].dst) && !fso.FileExists(moved[r].src)) {
          ensureDir(fso.GetParentFolderName(moved[r].src));
          fso.MoveFile(moved[r].dst, moved[r].src);
        }
      } catch (ignoreMove) {}
    }

    var restore = [
      { live: catalogue, backup: fso.BuildPath(txn, "catalogue.db.bak") },
      { live: manifest, backup: fso.BuildPath(txn, "downloads.db.bak") },
      { live: sources, backup: fso.BuildPath(txn, "sources.db.bak") }
    ];
    for (var q = 0; q < restore.length; q++) {
      try {
        if (fso.FileExists(restore[q].backup)) fso.CopyFile(restore[q].backup, restore[q].live, true);
      } catch (ignoreDb) {}
    }
    WScript.Quit(6);
  }
})();
