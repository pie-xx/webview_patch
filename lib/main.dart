import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
          setState(() {
            curURL = value;
          });
        },
        javascriptChannels: Set.from([
          JavascriptChannel(
            name: "rp_pickfile",
            onMessageReceived: (JavascriptMessage result) async {
              print("  ");
            }),
        ]),
        onWebViewCreated: (WebViewController webViewController) async {
          // 生成されたWebViewController情報を取得する
          _controller = webViewController;
        },
        debuggingEnabled: true,
      ),
    );
  }
}
