import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'post_service.dart';

class CreatePostWidget extends StatefulWidget {
  final PostService postService;
  final VoidCallback onPostCreated;

  const CreatePostWidget({
    super.key,
    required this.postService,
    required this.onPostCreated,
  });

  @override
  State<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends State<CreatePostWidget> {
  final TextEditingController _controller = TextEditingController();
  final List<File> _images = [];

  final ImagePicker _picker = ImagePicker();
  bool _loading = false;

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage();
    setState(() {
      _images.addAll(pickedFiles.map((e) => File(e.path)));
    });
    }

  Future<void> _submitPost() async {
    if (_controller.text.trim().isEmpty && _images.isEmpty) return;
    setState(() => _loading = true);

    try {
      await widget.postService.createPost(
        _controller.text.trim(),
        images: _images,
      );
      widget.onPostCreated();
      _controller.clear();
      _images.clear();
    } catch (e) {
      print('Create post failed: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to create post')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: "What's on your mind?",
              ),
              maxLines: null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _images
                  .map((file) => Stack(
                        children: [
                          Image.file(file, width: 80, height: 80, fit: BoxFit.cover),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => setState(() => _images.remove(file)),
                              child: const CircleAvatar(
                                radius: 10,
                                child: Icon(Icons.close, size: 14),
                              ),
                            ),
                          )
                        ],
                      ))
                  .toList(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.image),
                  label: const Text('Add Images'),
                ),
                ElevatedButton(
                  onPressed: _loading ? null : _submitPost,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Post'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
