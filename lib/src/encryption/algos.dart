abstract class EncryptionAlgo {
  const EncryptionAlgo();
}

// this should transform a stream;
class EncryptionBase64 extends EncryptionAlgo {
  const EncryptionBase64();
}

// here will be defined preset encryption algorithms with all parameters
// defined. For now though, base64 will be used as a placeholder to emulate encryption.

// class AES extends EncryptionAlgo {
//   const AES();
// }
// class RSA extends EncryptionAlgo {
//   const RSA();
// }
