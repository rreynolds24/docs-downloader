// Offline-compatible Windows Script Host documentation metadata index.
// Does not download any PDFs; only HTTPS HTML pages are retrieved with inbox curl.exe.
// Usage: cscript //nologo scripts\docs-index.js <products|index|check|status|reconcile> <runtime> [product|--preview]
(function () {
  var args=WScript.Arguments, mode=String(args.length?args.Item(0):"").toLowerCase();
  var fso=new ActiveXObject("Scripting.FileSystemObject"), shell=new ActiveXObject("WScript.Shell");
  if(args.length<2 || !/^(products|index|check|status|reconcile)$/.test(mode)){WScript.Echo("Usage: docs-index.js <products|index|check|status|reconcile> <runtime> [product|--preview]");WScript.Quit(2);}
  var runtime=fso.GetAbsolutePathName(String(args.Item(1))), scope=args.length>2?String(args.Item(2)):"";
  var db=fso.BuildPath(fso.BuildPath(runtime,"state"),"docs-index.db"), temp=fso.BuildPath(runtime,"temp");
  function mkdir(p){if(fso.FolderExists(p))return;var parent=fso.GetParentFolderName(p);if(parent&&!fso.FolderExists(parent))mkdir(parent);fso.CreateFolder(p);}
  function read(p){if(!fso.FileExists(p))return "";var h=fso.OpenTextFile(p,1,false,-2),s=h.ReadAll();h.Close();return s;}
  function write(p,s){var h=fso.CreateTextFile(p,true,false);h.Write(s);h.Close();}
  function clean(s){return String(s||"").replace(/[\r\n\t|]/g," ").replace(/^\s+|\s+$/g,"");}
  function uniq(a){var seen={},out=[];for(var i=0;i<a.length;i++){var k=a[i].toLowerCase();if(!seen[k]){seen[k]=true;out.push(a[i]);}}return out;}
  function matchLinks(html,path){var found=[],re=/<a\b[^>]*>/ig,m;while((m=re.exec(html))!==null){var h=m[0].match(/\bhref\s*=\s*["']([^"']+)["']/i);if(!h)continue;var v=h[1].replace(/&amp;/g,"&");if(v.indexOf(path)===0)found.push("https://docs.fortinet.com"+v);else if(v.indexOf("https://docs.fortinet.com"+path)===0)found.push(v.split(/[?#]/)[0]);}return uniq(found);}
  function pdfLink(html){var m,re=/<a\b[^>]*>/ig;while((m=re.exec(html))!==null){if(!/\bid\s*=\s*["']reader-pdf["']/i.test(m[0]))continue;var h=m[0].match(/\bhref\s*=\s*["']([^"']+)["']/i);if(h&&/^https:\/\//i.test(h[1]))return h[1].replace(/&amp;/g,"&");}return "";}
  function fetch(url){if(!/^https:\/\/docs\.fortinet\.com\/(?:product(?:\/|$)|document\/)/i.test(url))throw Error("Unapproved URL: "+url);
    mkdir(temp);var out=fso.BuildPath(temp,"docs-index-page.html");
    var cmd='cmd.exe /d /c curl.exe --ssl-revoke-best-effort -L --fail --silent --show-error --connect-timeout 15 --max-time 60 --proto "=https" --proto-redir "=https" "'+url+'" -o "'+out+'"';
    var rc=shell.Run(cmd,0,true);if(rc!==0)throw Error("HTTPS request failed: "+url+" ("+rc+")");
    return read(out);
  }
  function title(html){var m=html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);return clean(m?m[1].replace(/<[^>]*>/g,""):"");}
  function load(){var map={},lines=read(db).split(/\r?\n/);for(var i=0;i<lines.length;i++){if(!lines[i]||lines[i].charAt(0)==="#")continue;var f=lines[i].split("\t");if(f.length>=7)map[f[0]]=f;}return map;}
  function save(map){mkdir(fso.GetParentFolderName(db));var keys=[],s="#docs-index-v1\turl\tproduct\tversion\ttitle\tpdf_url\tpdf_filename\tlast_seen\r\n";for(var k in map)if(map.hasOwnProperty(k))keys.push(k);keys.sort();for(var i=0;i<keys.length;i++)s+=map[keys[i]].join("\t")+"\r\n";var pending=db+".new";write(pending,s);if(fso.FileExists(db))fso.DeleteFile(db,true);fso.MoveFile(pending,db);}
  function fields(url,html){var m=url.match(/^https:\/\/docs\.fortinet\.com\/document\/([^\/]+)\/([^\/]+)\//i);if(!m)return null;var pdf=pdfLink(html),name=pdf?decodeURIComponent(pdf.split(/[?#]/)[0].split("/").pop()):"";return [url,clean(m[1]),clean(m[2]),title(html),clean(pdf),clean(name),new Date().toUTCString()];}
  function products(){var html=fetch("https://docs.fortinet.com/product");var list=matchLinks(html,"/product/"),out=[];for(var i=0;i<list.length;i++){var m=list[i].match(/^https:\/\/docs\.fortinet\.com\/product\/([^\/?#]+)(?:\/|$)/);if(m)out.push(m[1]);}return uniq(out);}
  function resultCount(map){var n=0;for(var k in map)if(map.hasOwnProperty(k))n++;return n;}
  if(mode==="status"){var existing=load();WScript.Echo("Indexed documents : "+resultCount(existing));WScript.Echo("Index file        : "+db);WScript.Quit(0);}
  if(mode==="reconcile"){if(scope && scope!=="--preview"){WScript.Echo("[FAIL] Only --preview is supported; no local PDF moves are permitted.");WScript.Quit(2);}
    var idx=load(),byName={},amb={},root=fso.BuildPath(fso.BuildPath(runtime,"downloads"),"unclassified"),hits=0,unmatched=0;
    for(var key in idx)if(idx.hasOwnProperty(key)){var row=idx[key],fn=row[5].toLowerCase();if(!fn)continue;if(byName[fn]&&byName[fn]!==row[0])amb[fn]=true;else byName[fn]=row[0];}
    if(fso.FolderExists(root)){var en=new Enumerator(fso.GetFolder(root).Files);for(;!en.atEnd();en.moveNext()){var file=en.item();if(!/\.pdf$/i.test(file.Name))continue;var fn=file.Name.toLowerCase();if(byName[fn]&&!amb[fn]){hits++;WScript.Echo("CANDIDATE\t"+file.Name+"\t"+byName[fn]);}else{unmatched++;WScript.Echo((amb[fn]?"AMBIGUOUS":"UNRESOLVED")+"\t"+file.Name);}}}
    WScript.Echo("Unique filename candidates: "+hits+"; unresolved/ambiguous: "+unmatched+". No files moved.");WScript.Quit(0);
  }
  try{
    var ps=scope? [scope.replace(/^https:\/\/docs\.fortinet\.com\/product\//,"").split("/")[0]]:products();
    if(mode==="products"){for(var i=0;i<ps.length;i++)WScript.Echo(ps[i]);WScript.Echo("Products discovered: "+ps.length);WScript.Quit(0);}
    var map=load(),added=0,updated=0,fail=0,visited=0;
    for(var i=0;i<ps.length;i++){var p=ps[i], docUrls=[];if(!/^[a-z0-9][a-z0-9-]*$/i.test(p)){WScript.Echo("[WARN] Unsafe product token: "+p);fail++;continue;}
      try{docUrls=matchLinks(fetch("https://docs.fortinet.com/product/"+p),"/document/");
        for(var j=0;j<docUrls.length;j++){var url=docUrls[j];try{var r=fields(url,fetch(url));if(!r)continue;visited++;if(!map[url])added++;else if(map[url].slice(1,6).join("|")!==r.slice(1,6).join("|"))updated++;map[url]=r;}catch(ex){fail++;WScript.Echo("[WARN] "+clean(String(ex.message)));}}
      }catch(e){fail++;WScript.Echo("[WARN] "+clean(String(e.message)));}
      if(mode==="index")save(map);
      WScript.Echo("[INFO] "+p+": "+docUrls.length+" document links");
    }
    WScript.Echo("Documents indexed: "+visited+"; added: "+added+"; changed: "+updated+"; failed: "+fail);
    if(mode==="index")WScript.Echo("Index saved: "+db);else WScript.Echo("Read-only check; index unchanged.");
    WScript.Quit(fail?3:0);
  }catch(e){WScript.Echo("[FAIL] "+clean(String(e.message)));WScript.Quit(3);}
})();
