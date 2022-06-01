import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WebPageView(),
    );
  }
}

class WebPageView extends StatefulWidget {
  const WebPageView({Key? key, }) : super(key: key);

  @override
  State<WebPageView> createState() => _WebPageViewState();
}

Future<String> inputDialog(BuildContext context, String title, String initval ) async {
  final textController = TextEditingController();
  textController.text = initval;

  String? res = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: 
          TextField(
            controller: textController,
//              decoration: InputDecoration(hintText: "ここに入力"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.pop(context, textController.text );
              },
            ),
          ],
        );
      });
  return res ?? "";
}

class _WebPageViewState extends State<WebPageView> {
  late WebViewController _controller;
  String curURL = "https://";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text( curURL ),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () async {
              String url = await inputDialog(context, "URL", curURL);
              if( url!="") {
                _controller.loadUrl(url);
                setState(() {
                  curURL = url;
                });
              }
            }),
        ],
        leading:
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white,),
            tooltip: 'back',
            onPressed: () async {
              _controller.goBack();
            },
          ),
      ),
      body: WebView(
        javascriptMode: JavascriptMode.unrestricted,
        onPageFinished: (value) async {          
          await Future.delayed(const Duration(milliseconds: 500 ));
          
          _controller.runJavascript(
          """
            var ftlist = document.getElementsByTagName("input");
            for( var n=0; n < ftlist.length; ++n ){
              var ft = ftlist[n];
              if(ft.type=="file"){
                var ftid=ft.id;
                if(ftid==""){
                // idが付いてないときは、そのページに存在しないidをinputタグに付与
                  for( var i=0; i < 100; ++i){
                    ftid="ftid"+i;
                    if( document.getElementById(ftid)==null ){
                      break;
                    }
                  }
                  ft.id = ftid;
                }
                ft.addEventListener("click",(event)=>{ rp_pickfile.postMessage(event.target.id); });
              }
            }
          """);
          setState(() {
            curURL = value;
          });
        },
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
            name: "rp_pickfile",
            onMessageReceived: (JavascriptMessage result) async {
              FilePickerResult? fpresult = await FilePicker.platform.pickFiles(type: FileType.any);
              if (fpresult != null) {
                String fpath = fpresult.files.single.path??"";
                File file = File(fpath);
                Uint8List bindata = await file.readAsBytes();
                List<int> binlist = bindata.buffer.asUint8List();
                String dataURI = Uri.dataFromBytes(binlist).toString();
                
                _controller.runJavascript(
                  """
                  var dataURI = "$dataURI";
                  var inputtag = document.getElementById("${result.message}");
                  var byteString = atob( dataURI.split( "," )[1] ) ;
                  var dl = dataURI.match( /(:)([-a-z\/]+)(;)/ );
                  var mimeType = "application/octet-stream";
                  for( var i=0, l=byteString.length, content=new Uint8Array( l ); l>i; i++ ) {
                    content[i] = byteString.charCodeAt( i ) ;
                  }
                  var blob = new Blob( [ content ], {
                    type: mimeType ,
                  } ) ;

                  var imgFile = new File([blob], '${basename(fpath)}', {type: "application/octet-stream"});
                  var dt = new DataTransfer();
                  dt.items.add(imgFile);
                  inputtag.files = dt.files;
                  var event = new Event("change");
                  inputtag.dispatchEvent(event);
                  """
                );
              }
            }),
          },
        onWebViewCreated: (WebViewController webViewController) async {
          // 生成されたWebViewController情報を取得する
          _controller = webViewController;
        },
        debuggingEnabled: true,
      ),
    );
  }
}
