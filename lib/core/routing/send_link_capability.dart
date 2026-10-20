/// Splits a send-link fragment into the AES key and the access token.
///
/// The fragment is `{aesKey}&a={accessToken}`. The AES key is everything
/// before `&a=`. A link that only carries the key has an empty access token.
({String aesKey, String accessToken}) splitFragmentCapability(String fragment) {
  const marker = '&a=';
  final index = fragment.indexOf(marker);
  if (index < 0) return (aesKey: fragment, accessToken: '');
  return (
    aesKey: fragment.substring(0, index),
    accessToken: fragment.substring(index + marker.length),
  );
}
