import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sound/flutter_sound.dart';

VideoPlayerController? _videoController;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.blue[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController roomController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedRoomCode = prefs.getString('roomCode');
    String? savedUsername = prefs.getString('username');

    if (savedRoomCode != null && savedUsername != null) {
      roomController.text = savedRoomCode;
      usernameController.text = savedUsername;
      navigateToChatScreen(savedRoomCode, savedUsername);
    }
  }

  void navigateToChatScreen(String roomCode, String username) {
    if (roomCode.isNotEmpty && username.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(roomCode: roomCode, username: username),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code and username')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat App Home'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to Chat App',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: roomController,
              decoration: InputDecoration(
                labelText: 'Room Code',
                prefixIcon: const Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                String roomCode = roomController.text.trim();
                String username = usernameController.text.trim();

                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setString('roomCode', roomCode);
                prefs.setString('username', username);

                navigateToChatScreen(roomCode, username);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 5,
              ),
              child: const Text(
                'Join Room',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String roomCode;
  final String username;

  const ChatPage({super.key, required this.roomCode, required this.username});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late IO.Socket socket;
  List<Map<String, dynamic>> messages = [];
  final TextEditingController messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  ScrollController _scrollController = ScrollController();

  late FlutterSoundRecorder _recorder;
  bool _isRecording = false;
  String _recordedFilePath = '';

  @override
  void initState() {
    super.initState();
    connectToServer();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
  _recorder = FlutterSoundRecorder();
  try {
    await _recorder.openRecorder();
    if (!await _recorder.isEncoderSupported(Codec.aacADTS)) {
      throw Exception("AAC codec is not supported on this platform.");
    }
  } catch (e) {
    debugPrint("Recorder initialization failed: $e");
  }
}


  void connectToServer() {
    socket = IO.io('http://192.168.158.223:3000', IO.OptionBuilder().setTransports(['websocket']).build());

    socket.onConnect((_) {
      socket.emit('join room', {'roomCode': widget.roomCode, 'username': widget.username});
    });

    socket.on('chat message', (data) {
      addMessage({
        'username': data['username'],
        'message': data['message'],
        'type': 'text',
      });
    });

    socket.on('media message', (data) {
      addMessage({
        'username': data['username'],
        'message': data['message'],
        'type': data['type'],
      });
    });
  }

  void addMessage(Map<String, dynamic> message) {
    setState(() {
      messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _startStopRecording() async {
  if (_isRecording) {
    String? path = await _recorder.stopRecorder();
    if (path != null) {
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
      _sendVoiceMessage(_recordedFilePath);
    }
  } else {
    try {
      await _recorder.startRecorder(
        toFile: 'voice_message.aac',
        codec: Codec.aacADTS, // Specify AAC codec
      );
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      debugPrint("Error starting recorder: $e");
    }
  }
}


  Future<void> _sendVoiceMessage(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64String = base64Encode(bytes);

    socket.emit('send media', {
      'username': widget.username,
      'message': base64String,
      'type': 'audio',
    });
  }

  void leaveRoom() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove('roomCode');
    prefs.remove('username');

    socket.emit('leave room', {'roomCode': widget.roomCode, 'username': widget.username});
    socket.disconnect();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.dispose();
    }
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomCode}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: leaveRoom,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) => buildMessageBubble(messages[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo),
                  onPressed: () async {
                    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      final bytes = await pickedFile.readAsBytes();
                      final base64String = base64Encode(bytes);
                      socket.emit('send media', {
                        'username': widget.username,
                        'message': base64String,
                        'type': 'image',
                      });
                    }
                  },
                ),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  onPressed: _startStopRecording,
                ),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          final message = messageController.text.trim();
                          if (message.isNotEmpty) {
                            socket.emit('chat message', {'username': widget.username, 'message': message});
                            messageController.clear();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMessageBubble(Map<String, dynamic> message) {
    final isSelf = message['username'] == widget.username;
    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelf ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(15),
        ),
        child: message['type'] == 'image'
            ? Image.memory(base64Decode(message['message']), width: 200, height: 200, fit: BoxFit.cover)
            : Text(
                message['message'],
                style: TextStyle(color: isSelf ? Colors.white : Colors.black),
              ),
      ),
    );
  }
}
