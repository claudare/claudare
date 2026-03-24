abstract class Memento<T> {
  const Memento();

  String stringify(T value);
  T parse(String str);
}
