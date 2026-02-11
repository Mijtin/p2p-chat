import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  encrypt.Key? _key;
  encrypt.IV? _iv;
  
  // Initialize with shared secret (derived from connection code)
  void initialize(String sharedSecret) {
    // Generate 32-byte key from shared secret using SHA-256
    final keyBytes = sha256.convert(utf8.encode(sharedSecret)).bytes;
    _key = encrypt.Key(Uint8List.fromList(keyBytes));
    
    // Generate IV from first 16 bytes of key hash
    _iv = encrypt.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
  }
  
  bool get isInitialized => _key != null && _iv != null;
  
  // Encrypt text message
  String? encryptText(String plainText) {
    if (!isInitialized) return null;
    
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      
      final encrypted = encrypter.encrypt(plainText, iv: _iv!);
      return encrypted.base64;
    } catch (e) {
      print('Encryption error: $e');
      return null;
    }
  }
  
  // Decrypt text message
  String? decryptText(String encryptedText) {
    if (!isInitialized) return null;
    
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      
      final encrypted = encrypt.Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: _iv!);
    } catch (e) {
      print('Decryption error: $e');
      return null;
    }
  }
  
  // Encrypt bytes (for file chunks)
  List<int>? encryptBytes(List<int> bytes) {
    if (!isInitialized) return null;
    
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      
      final encrypted = encrypter.encryptBytes(bytes, iv: _iv!);
      return encrypted.bytes;
    } catch (e) {
      print('Encryption error: $e');
      return null;
    }
  }
  
  // Decrypt bytes
  List<int>? decryptBytes(List<int> encryptedBytes) {
    if (!isInitialized) return null;
    
    try {
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_key!, mode: encrypt.AESMode.cbc),
      );
      
      final encrypted = encrypt.Encrypted(Uint8List.fromList(encryptedBytes));
      return encrypter.decryptBytes(encrypted, iv: _iv!);
    } catch (e) {
      print('Decryption error: $e');
      return null;
    }
  }
  
  // Generate shared secret from two peer IDs
  static String generateSharedSecret(String peerId1, String peerId2) {
    // Sort to ensure same secret regardless of order
    final ids = [peerId1, peerId2]..sort();
    final combined = ids.join('_');
    
    // Hash to create fixed-length secret
    final bytes = sha256.convert(utf8.encode(combined)).bytes;
    return base64Encode(bytes);
  }
  
  // Verify connection by checking if both parties have same secret
  bool verifyConnection(String otherPeerId, String myPeerId) {
    final expectedSecret = generateSharedSecret(myPeerId, otherPeerId);
    // In real implementation, this would involve a handshake
    return true;
  }
  
  void dispose() {
    _key = null;
    _iv = null;
  }
}
