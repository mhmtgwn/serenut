// lib/presentation/pages/admin/ticket_chat_page.dart
// Serenut POS — Support Ticket Chat Thread Page (Sprint 10)
// Interactive messaging bubble layout for support tickets replies.
// Created: 04 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/infrastructure/repositories/portal_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kBgColor       = Color(0xFFF1F5F9);
const _kBorderColor   = Color(0xFFE2E8F0);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBlue          = Color(0xFF3B82F6);

class TicketChatPage extends ConsumerStatefulWidget {
  final String ticketId;
  final String ticketTitle;

  const TicketChatPage({
    super.key,
    required this.ticketId,
    required this.ticketTitle,
  });

  @override
  ConsumerState<TicketChatPage> createState() => _TicketChatPageState();
}

class _TicketChatPageState extends ConsumerState<TicketChatPage> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portalRepo = ref.watch(portalRepositoryProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: _kTextPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.ticketTitle,
              style: const TextStyle(color: _kTextPrimary, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
            const Text(
              'Destek Ekibi İletişim Hattı',
              style: TextStyle(color: _kTextSecondary, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // Message History
          Expanded(
            child: FutureBuilder<List<TicketMessage>>(
              future: portalRepo.getTicketMessages(widget.ticketId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Mesajlar yüklenemedi: ${snapshot.error}'));
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(child: Text('Henüz mesaj gönderilmemiş.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  reverse: false, // Normal order
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderName != 'Support Agent' && msg.senderName != 'admin';
                    final date = DateTime.tryParse(msg.createdAt) ?? DateTime.now();

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? _kBlue : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                msg.senderName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: _kBlue),
                              ),
                            if (!isMe) const SizedBox(height: 4),
                            Text(
                              msg.message,
                              style: TextStyle(color: isMe ? Colors.white : _kTextPrimary, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                DateFormat('HH:mm').format(date),
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : _kTextSecondary,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Send Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _kBlue,
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final portalRepo = ref.read(portalRepositoryProvider);
      await portalRepo.replyTicket(widget.ticketId, text);
      _messageController.clear();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesaj gönderilemedi: $e')),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }
}
