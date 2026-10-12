// Fortinet Docs Downloader native Windows Script Host parser.
// Usage:
//   cscript //nologo scripts\fortinet-parser.js solution <html> <out>
//   cscript //nologo scripts\fortinet-parser.js hubs <html> <out>
//   cscript //nologo scripts\fortinet-parser.js readerpdf <html> <out>
//   cscript //nologo scripts\fortinet-parser.js sitemap-index <xml> <out>
//   cscript //nologo scripts\fortinet-parser.js sitemap <xml> <out> <category-path>
//   cscript //nologo scripts\fortinet-parser.js kb-categories <html> <out>

(function () {
  var args = WScript.Arguments;
  if (args.length < 3) {
    WScript.Echo("Usage: fortinet-parser.js <mode> <input> <output> [filter]");
    WScript.Quit(2);
  }

  var mode = String(args.Item(0)).toLowerCase();
  var input = args.Item(1);
  var output = args.Item(2);
  var filter = args.length > 3 ? String(args.Item(3)).toLowerCase() : "";

  function readAll(path) {
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var f = fso.OpenTextFile(path, 1, false, -2);
    var s = f.ReadAll();
    f.Close();
    return s;
  }

  function writeLines(path, lines) {
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var f = fso.CreateTextFile(path, true, false);
    for (var i = 0; i < lines.length; i++) f.WriteLine(lines[i]);
    f.Close();
  }

  function decode(s) {
    return String(s)
      .replace(/&amp;/gi, "&")
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/\\\//g, "/");
  }

  function uniqPush(out, seen, value) {
    var k = value.toLowerCase();
    if (!seen[k]) {
      seen[k] = true;
      out.push(value);
    }
  }

  var s = readAll(input);
  var out = [];
  var seen = {};
  var m, re;

  if (mode === "solution") {
    re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>/ig;
    while ((m = re.exec(s)) !== null) {
      var href = decode(m[1]);
      var lower = href.toLowerCase();

      if (lower.indexOf("/document/") === 0) {
        uniqPush(out, seen, "DOC|https://docs.fortinet.com" + href);
      } else if (lower.indexOf("https://docs.fortinet.com/document/") === 0) {
        uniqPush(out, seen, "DOC|" + href);
      } else if (
        lower.indexOf("https://www.fortinet.com/") === 0 &&
        lower.indexOf(".pdf") > 0
      ) {
        uniqPush(out, seen, "PDF|" + href);
      } else if (
        lower.indexOf("https://fortinetweb.s3.amazonaws.com/") === 0 &&
        lower.indexOf(".pdf") > 0
      ) {
        uniqPush(out, seen, "PDF|" + href);
      }
    }
  } else if (mode === "hubs") {
    re = /<a\b([^>]*)>/ig;
    while ((m = re.exec(s)) !== null) {
      var tag = m[0];
      if (!/data-analytics\s*=\s*["']solution-hubs["']/i.test(tag)) continue;
      var hm = /href\s*=\s*["']([^"']+)["']/i.exec(tag);
      if (!hm) continue;
      var h = decode(hm[1]);
      if (h.indexOf("/") === 0) h = "https://docs.fortinet.com" + h;
      if (h.toLowerCase().indexOf("https://docs.fortinet.com/") === 0) {
        uniqPush(out, seen, h);
      }
    }
  } else if (mode === "readerpdf") {
    re = /<a\b[^>]*\bid\s*=\s*["']reader-pdf["'][^>]*>/ig;
    m = re.exec(s);
    if (m) {
      var rm = /href\s*=\s*["']([^"']+)["']/i.exec(m[0]);
      if (rm) out.push(decode(rm[1]));
    } else {
      re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*\bid\s*=\s*["']reader-pdf["'][^>]*>/ig;
      m = re.exec(s);
      if (m) out.push(decode(m[1]));
    }
  } else if (mode === "sitemap-index") {
    re = /<loc>([^<]+)<\/loc>/ig;
    while ((m = re.exec(s)) !== null) {
      var loc = decode(m[1]);
      if (/sitemap-topics-\d+\.xml$/i.test(loc)) uniqPush(out, seen, loc);
    }
  } else if (mode === "sitemap") {
    var blocks = s.split(/<url>/i);
    for (var bi = 1; bi < blocks.length; bi++) {
      var end = blocks[bi].indexOf("</url>");
      var block = end >= 0 ? blocks[bi].substring(0, end) : blocks[bi];
      var lm = /<loc>([^<]+)<\/loc>/i.exec(block);
      if (!lm) continue;
      var url = decode(lm[1]);
      if (filter && url.toLowerCase().indexOf(filter) < 0) continue;
      var dm = /<lastmod>([^<]+)<\/lastmod>/i.exec(block);
      var lastmod = dm ? decode(dm[1]) : "-";
      var im = /-(\d+)$/.exec(url);
      var articleId = im ? im[1] : "-";
      uniqPush(out, seen, url + "|" + lastmod + "|" + articleId);
    }
  } else if (mode === "kb-categories") {
    re = /<article\b[^>]*knowledge-base__card[\s\S]*?<\/article>/ig;
    while ((m = re.exec(s)) !== null) {
      var block = m[0];
      var am = /<a\b[^>]*>/i.exec(block);
      var tm = /<h3\b[^>]*>([^<]+)<\/h3>/i.exec(block);
      if (!am || !tm || !/\bcard_url\b/i.test(am[0])) continue;
      var um = /href\s*=\s*["']([^"']+)["']/i.exec(am[0]);
      if (!um) continue;
      var u = decode(um[1]);
      var title = decode(tm[1]).replace(/\|/g, "/");
      if (u.toLowerCase().indexOf("https://community.fortinet.com/") === 0) {
        uniqPush(out, seen, title + "|" + u);
      }
    }
  } else {
    WScript.Echo("Unknown mode: " + mode);
    WScript.Quit(2);
  }

  writeLines(output, out);
  WScript.Quit(out.length > 0 ? 0 : 1);
})();
