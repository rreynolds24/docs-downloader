// FortiMail Workspace Security: archive public MadCap HTML topics, never execute them.
// Windows Script Host JScript (ES3), inbox tools only.
(function () {
    var origin = "https://docs.perception-point.io/fortinet/";
    var prefix = origin + "Content/";
    var sitemap = origin + "Sitemap.xml";
    var maxTopics = 1000, maxBytes = 8388608;
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    var shell = new ActiveXObject("WScript.Shell");
    var args = WScript.Arguments;
    var mode = args.length ? String(args(0)).toLowerCase() : "";
    if (args.length !== 2 || !/^(inventory|check|download|selftest)$/.test(mode)) {
        WScript.Echo("Usage: workspace-security.js <inventory|check|download|selftest> <runtime>");
        WScript.Quit(2);
    }

    function fail(reason) { throw new Error(reason); }
    function read(path) {
        var file = fso.OpenTextFile(path, 1);
        try { return file.ReadAll(); } finally { file.Close(); }
    }
    function write(path, value) {
        var file = fso.CreateTextFile(path, false);
        try { file.Write(value); } finally { file.Close(); }
    }
    function mkdir(path) {
        if (fso.FolderExists(path)) return;
        var parent = fso.GetParentFolderName(path);
        if (!parent || parent === path) fail("Cannot create archive directory.");
        mkdir(parent);
        try { fso.CreateFolder(path); } catch (e) { if (!fso.FolderExists(path)) throw e; }
    }
    function join(base, child) { return fso.BuildPath(base, child); }
    function quoted(path) {
        if (/["%!\r\n]/.test(path)) fail("Unsupported command path.");
        return '"' + path + '"';
    }
    function topicPath(url) {
        if (url.indexOf(prefix) !== 0) return null;
        var rel = url.substr(prefix.length);
        // Do not decode escaped separators. Reject traversal, device names, and Windows trailing dots.
        if (!/^(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*\/)+[A-Za-z0-9_-][A-Za-z0-9_.-]*\.html?$/i.test(rel)) return null;
        if (/(^|\/)(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:[.\/]|$)|\.(?:\/|$)/i.test(rel)) return null;
        return rel;
    }
    function parseSitemap(xml) {
        if (!/<urlset(?:\s|>)/i.test(xml) || !/<\/urlset\s*>\s*$/i.test(xml))
            fail("Expected a complete vendor sitemap, not an error or sign-in page.");
        var re = /<loc\s*>\s*([^<]+?)\s*<\/loc\s*>/gi, match, result = [], seen = {};
        while ((match = re.exec(xml)) !== null) {
            var url = match[1], path = topicPath(url);
            if (!path) continue;
            var key = "$" + path.toLowerCase();
            if (seen[key] && seen[key] !== url) fail("Case-colliding topic paths in vendor sitemap.");
            if (seen[key]) continue;
            seen[key] = url;
            result.push({url:url, path:path});
            if (result.length > maxTopics) fail("Vendor topic limit exceeded.");
        }
        if (!result.length) fail("No in-scope HTML topics in the vendor sitemap.");
        return result;
    }
    function validTopic(html) {
        return /<html\b[^>]*\bdata-mc-runtime-file-type\s*=\s*["']Topic(?:;[^"']*)?["']/i.test(html)
            && /<body(?:\s|>)/i.test(html) && /<\/html\s*>\s*$/i.test(html);
    }
    function fetch(url, out) {
        if (url !== sitemap && !topicPath(url)) fail("URL is outside the supported public documentation source.");
        var headers = out + ".headers";
        // Do not follow a redirect to a login flow, different host, or another path.
        var cmd = 'curl.exe -q --ssl-revoke-best-effort --proto "=https" --fail --silent --show-error'
                + ' --connect-timeout 15 --max-time 45 --max-filesize ' + maxBytes
                + ' --dump-header ' + quoted(headers) + ' --output ' + quoted(out) + ' ' + quoted(url);
        var rc = shell.Run(cmd, 0, true);
        if (rc !== 0 || !fso.FileExists(headers) || !fso.FileExists(out)) fail("curl failed (" + rc + ").");
        var statuses = read(headers).match(/^HTTP\/[0-9.]+\s+[0-9]{3}(?=\s|$)/gim);
        if (!statuses || !/^HTTP\/[0-9.]+\s+200$/i.test(statuses[statuses.length-1]))
            fail("Expected HTTP 200; redirects are not followed.");
        if (fso.GetFile(out).Size < 1 || fso.GetFile(out).Size > maxBytes) fail("Invalid response size.");
    }
    function digest(path) {
        var proc = shell.Exec("certutil.exe -hashfile " + quoted(path) + " SHA256");
        var output = proc.StdOut.ReadAll();
        if (proc.ExitCode !== 0) fail("Could not hash topic.");
        var lines = output.split(/\r?\n/), i, line;
        for (i = 0; i < lines.length; i++) {
            line = lines[i].replace(/\s/g, "");
            if (/^[0-9a-f]{64}$/i.test(line)) return line.toLowerCase();
        }
        fail("No SHA-256 digest in certutil output.");
    }
    function copySnapshot(topic, data, destination, operation) {
        if (!validTopic(read(data))) fail("Response is not a complete MadCap documentation topic.");
        var sha = digest(data);
        // Keep original bytes and versions. Use .txt so the archive does not launch active HTML.
        var folder = join(destination, topic.path.replace(/\//g, "\\"));
        var target = join(folder, sha + ".htm.txt");
        if (target.length > 247) fail("Archive path too long; use a shorter installation directory.");
        if (fso.FileExists(target)) {
            if (digest(target) !== sha) fail("Existing snapshot hash mismatch; not overwritten.");
            return "unchanged";
        }
        if (operation === "check") return "missing";
        mkdir(folder);
        try { fso.MoveFile(data, target); }
        catch (e) {
            if (fso.FileExists(target) && digest(target) === sha) return "unchanged";
            throw e;
        }
        return "saved";
    }
    function removeTemporary(path) {
        if (fso.FileExists(path)) fso.DeleteFile(path);
    }
    function operate(operation, work, destination, acquire) {
        var mapfile = join(work, "map.xml"), data = join(work, "page.tmp"), i, topic, result;
        var totals = {found:0, saved:0, missing:0, unchanged:0, failed:0};
        acquire(sitemap, mapfile);
        var topics = parseSitemap(read(mapfile));
        totals.found = topics.length;
        for (i = 0; i < topics.length; i++) {
            topic = topics[i];
            if (operation === "inventory") { WScript.Echo(topic.url); continue; }
            try {
                acquire(topic.url, data);
                result = copySnapshot(topic, data, destination, operation);
                totals[result]++;
            } catch (e) {
                totals.failed++;
                if (acquire === fetch) WScript.Echo("[WARN] " + topic.url + " : " + (e.description || e.message));
            } finally {
                removeTemporary(data);
                removeTemporary(data + ".headers");
            }
        }
        return totals;
    }
    function runSelftest(work) {
        function assert(value, message) { if (!value) fail(message); }
        var sample = prefix + "PP/Test.htm";
        function map(values) {
            return "<urlset>" + values.join("").replace(/<loc>/g, "<url><loc>")
                .replace(/<\/loc>/g, "</loc></url>") + "</urlset>";
        }
        function loc(url) { return "<loc>" + url + "</loc>"; }
        var xml = map([loc(sample), loc(sample), loc(prefix + "PP/Img.png"),
            loc(prefix + "PP/../No.htm"), loc(prefix + "PP/%2e%2e/No.htm"),
            loc(prefix + "PP./No.htm"), loc(prefix + "PP/NUL.htm"),
            loc("https://docs.perception-point.io.example/fortinet/Content/PP/No.htm"),
            loc("https://docs.perception-point.io/WP/Content/PP/No.htm"),
            loc(sample + "?key=anything"), loc(sample + "#fragment")]);
        var items = parseSitemap(xml);
        assert(items.length === 1 && items[0].url === sample, "Sitemap scope/dedup fixture failed.");
        function rejects(s) { try { parseSitemap(s); } catch (e) { return true; } return false; }
        assert(rejects("<html>Secure Login</html>"), "Login sitemap not rejected.");
        assert(rejects(map([loc(sample), loc(prefix + "PP/test.htm")])), "Case collision not rejected.");
        var revision = "one", broken = false, requests = 0;
        function fixture(url, path) {
            requests++;
            if (url === sitemap) write(path, xml);
            else if (url === sample) write(path, broken ? "<html><body>Secure Login</body></html>"
                : '<html data-mc-runtime-file-type="Topic;Default"><body>' + revision + '</body></html>');
            else fail("Unexpected fixture fetch.");
        }
        function trial(m, name) {
            var d = join(work, name);
            mkdir(d);
            return operate(m, d, join(work, "archives"), fixture);
        }
        assert(trial("inventory", "inventory").found === 1 && requests === 1, "Inventory fetched topic body.");
        assert(trial("check", "check-before").missing === 1 && !fso.FolderExists(join(work, "archives")),
            "Check should not create archive files.");
        assert(trial("download", "first").saved === 1, "First snapshot not saved.");
        var history = join(join(work, "archives"), "PP\\Test.htm");
        var files = new Enumerator(fso.GetFolder(history).Files);
        var first = String(files.item().Path), firstHash = digest(first);
        assert(/\.htm\.txt$/i.test(first) && /one/.test(read(first)), "Original archived bytes missing.");
        assert(trial("download", "repeat").unchanged === 1, "Duplicate snapshot not skipped.");
        revision = "two";
        assert(trial("download", "changed").saved === 1 && digest(first) === firstHash
            && fso.GetFolder(history).Files.Count === 2, "Prior revision was not preserved.");
        broken = true;
        assert(trial("download", "auth").failed === 1 && fso.GetFolder(history).Files.Count === 2,
            "Sign-in response entered archive.");
        WScript.Echo("[PASS] Workspace Security topic archive self-test");
    }

    var work = null, status = 0;
    try {
        var runtime = fso.GetAbsolutePathName(String(args(1)));
        quoted(runtime);
        var temp = join(runtime, "temp");
        mkdir(temp);
        work = join(temp, fso.GetTempName());
        fso.CreateFolder(work);
        if (mode === "selftest") runSelftest(work);
        else {
            var dest = join(runtime, "downloads\\products\\fortimail-workspace-security\\web");
            var t = operate(mode, work, dest, fetch);
            WScript.Echo("HTML topics discovered : " + t.found);
            if (mode !== "inventory") {
                WScript.Echo("New/changed snapshots  : " + (mode === "check" ? t.missing : t.saved));
                WScript.Echo("Unchanged snapshots    : " + t.unchanged);
                WScript.Echo("Failed topics          : " + t.failed);
                WScript.Echo(mode === "check" ? "Read-only check; archive unchanged." : "Archive: " + dest);
                if (t.failed) status = 4;
            }
        }
    } catch (e) {
        WScript.Echo("[FAIL] Workspace Security: " + (e.description || e.message));
        status = 3;
    } finally {
        if (work && fso.FolderExists(work)) fso.DeleteFolder(work, true);
    }
    WScript.Quit(status);
}());
