# block encryption implementation

I have no idea what I am doing here... this should be good enough for testing,
but really insufficient for real use. Credits go to Claude 3.5 Sonnet on this one.

This implementation uses [pointycastle library](https://pub.dev/packages/pointycastle)

The blob storage will use a new key per file. All these keys will be stored in
a set, and will be replicated to other devices.
It does seem wrong to send encrypted encryption keys over the network, but I
think its better then just using a single key for all operations?
The "keychain" store is replicated though events, similarly to how the application
works normally. The keychain changes are blended into the normal operation.
