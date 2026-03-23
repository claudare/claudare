abstract class Memento<T> {
  const Memento();

  String Function(T) stringify();
  T parse(String str);
}
