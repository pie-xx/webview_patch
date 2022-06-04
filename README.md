# webview_patch

FlutterでHTMLコンテンツを表示するときは、公式のwebview_flutterを使うのが定番だと思いますが、Androidのwebview_flutterには&lt;input type="file"&gt;のファイル選択が動かないというバグがあります。(2022-06-01時点) とあるアプリを作っていて、どうしてもその機能を使ったサーバーコンテンツを表示する必要があり、なんとかしようとしたのがこの記事のきっかけです。
どうやったのか結論を先に言うと次のとおりになります。
1. ページ読込時にinputタグのクリックイベントを監視するJavascript関数を仕掛ける
2. inputタグがクリックされたら、Flutterにコールバックする
3. コールバックされたFlutter側でファイル選択し、選ばれたファイルをDataURI化してinputタグに書き戻す

言ってみればバッドノウハウなのでwebview_flutterが修正されれば用済みの話なんですが、同じやり方でサーバー側のページの内容を書き換えたり、ページからFlutterの機能を使ったりするのにも使える方法なので、覚えていて損はないですよ。
# FlutterとWebViewのインターフェース
webview_flutterではWebViewに任意のJavascriptを実行させたり、WebView上のJavascriptからFlutter内の処理を呼び出すことができますが、その方法をおさらいしておきましょう。
## FlutterからWebViewにJavascriptを実行させる
FlutterからWebViewを呼び出すにはWebViewControllerを使うので、まずWebView表示するクラスでメンバーを定義します。
```dart
class _WebPageViewState extends State<WebPageView> {
  late WebViewController _controller;
```
WebViewControllerはonWebViewCreated:で通知されるので、そこで保存します。
```dart
onWebViewCreated: (WebViewController webViewController) {
  _controller = webViewController;
},
```
WebViewにJavascriptを実行させたいときは、走らせたいスクリプトをパラメータにして_controllerのrunJavascriptメソッドを呼び出します。
```dart
  _controller.runJavascript("alert('hello!');");
```

## WebviewからFlutter内の処理を呼び出す
webview_flutterにJavascriptChannelを設定しておくと、Javascriptからそのチャネルを使ってFlutter側の処理を呼び出すことができます。JavascriptChannelの設定方法は次のとおりです。
```dart
javascriptChannels: <JavascriptChannel>{
  JavascriptChannel(
    name: "rp_pickfile",  // Javascriptから呼び出すときのオブジェクト名となる
    onMessageReceived: (JavascriptMessage result) {
      // Javascriptから呼び出されたときの処理を書く
    }
  ),
  }
```
rp_pickfileという名前でチャネルを設定しておくと、Javascriptからは次のように呼び出すことができます。
```javascript
rp_pickfile.postMessage("Flutterに伝えたい文字列");
```
postMessageのパラメータは、JavascriptChannelのonMessageReceivedではresult.messageで受け取ることができます。
# ページ読み込み時にinputタグを監視するJavascriptを仕掛ける
webview_flutterではページ読み込みが完了すると、onPageFinished:で指定した関数が呼ばれるので、そこでページ内にある&lt;input type="file"&gt;のタグを探して、クリックされたらFlutterにコールバックするようイベントを監視するものを仕掛けます。具体的にはそういうことをするJavascriptをWebviewに送ってやるわけです。
```dart
onPageFinished: (value) {          

  _controller.runJavascript(
  """
    var ftlist = document.getElementsByTagName("input");
    for( var n=0; n < ftlist.length; ++n ){
      var ft = ftlist[n];
      if(ft.type=="file"){
        if(ft.id==""){
	      ft.id = "ft"+n; // inputタグにidがなければ付けてしまう。
	    }
	  ft.addEventListener("click",(event)=>{
	  // クリックされたら自分のidをFlutterに通知
	  rp_pickfile.postMessage(event.target.id); 
	});
      }
    }
  """);
```
まずdocument.getElementsByTagName("input"); でinputタグを探して、type="file"だったら、addEventListenerでコールバックを仕掛けます。どのタグからのコールバックかFlutter側で知るために、パラメータにinputタグのidが必要なのですが、元のタグにidが設定されてないときは、適当なidをむりやりつけています。
ここで注意しなければならないのは、addEventListenerで指定した関数が評価されるのは、実際にイベントが発生したとき、つまりinputタグがクリックされたときです。なので、次のようなコードは正しく機能しません。
```dart
    for( var n=0; n < ftlist.length; ++n ){
      ...略
        ft.id = "ft"+n;
        ft.addEventListener("click",(event)=>{
	  rp_pickfile.postMessage("ft"+n); 
	});
    }
```
一見、nの値が変化してループするのでタグごとに違うidがセットされて、イベント発生時にそれが通知されるように見えますが、nが評価されるのはイベント発生時なので、どのタグをクリックしてもnの値はループを抜けたときの値となって見分けがつきません。

# Flutterからwebviewへバイナリデータを渡す
イベントリスナーの設定がうまくいけば、inputタグをクリックするとFlutterへコールバックされるようになります。Flutter側でやることは、まずはJavascriptChannelでコールバックの飛び先を設定することと、コールバックされたらファイル選択メニューを表示してファイルを選択し、中身を文字列にしてWebView内のinputタグへ返すことです。
## 選択したファイルをDataURI形式に変換
&lt;input type="file"&gt;でアップロードするファイルは画像などのバイナリーデータですが、FlutterからWebViewに情報を送るにはJavascriptにする必要があります。このためバイナリーデータをDataURI文字列に変換します。
```dart
import 'package:file_picker/file_picker.dart';
...略
FilePickerResult? fpresult = await FilePicker.platform.pickFiles(type: FileType.any);
if (fpresult != null) {
  String fpath = fpresult.files.single.path??"";
  Uint8List bindata = await File(fpath).readAsBytes();
  List<int> binlist = bindata.buffer.asUint8List();
  String dataURI = Uri.dataFromBytes(binlist).toString();
```
ファイル選択はFilePickerプラグインを使っています。pubspec.yamlにインストールしてくだい。
## 文字列化したデータをJavascriptでinputタグにセットする
転送すべきデータが入ったdataURIを含んだJavascript作成し、WebViewに実行させます。まずはdataURIの文字列からblobオブジェクトを作りバイナリFileオブジェクトとして格納する部分まで。
```dart
_controller.runJavascript(
  """
  var dataURI = "$dataURI";
  var byteString = atob( dataURI.split( "," )[1] ) ;
  var mimeType = "application/octet-stream";
  for( var i=0, l=byteString.length, content=new Uint8Array( l ); l<i; i++ ) {
    content[i] = byteString.charCodeAt( i ) ;
  }
  var blob = new Blob( [ content ], {
    type: mimeType ,
  } ) ;
  var imgFile = new File([blob], '${basename(fpath)}', {type: "application/octet-stream"});
```
後半はFileオブジェクトをinputタグに設定します。result.messageはコールバックのパラメータで、inputタグのidが格納されています。
```dart
  var inputtag = document.getElementById("${result.message}");
  var dt = new DataTransfer();
  dt.items.add(imgFile);
  inputtag.files = dt.files;
  var event = new Event("change");
  inputtag.dispatchEvent(event);
  """
);
```
webview_flutterはファイル選択が動作しないだけで、その部分を以上のようにFlutterで肩代わりさせてやれば、あとはsubmitで送信などは正常に行えます。厳密にはのmultiple属性で複数選択したり、capture属性でカメラを起動したりする必要がありますが、頑張ればなんとかなるのではないでしょうか。

ページ読込時にJavascriptでページを書き換える、DataURIでバイナリーデータを送り込む、などを駆使すれば、ボタンを追加するとか画像を書き換えるとかやり放題なので、アプリ中にサーバーサイドの画面を表示するとき都合の悪い部分に手をいれたれするのに使えると思います。

サンプルソースは以下の場所にあります
https://github.com/pie-xx/webview_patch
## 参考
https://lab.syncer.jp/Web/JavaScript/Snippet/26/
https://qiita.com/jkr_2255/items/1c30f7afefe6959506d2
