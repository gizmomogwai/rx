/+++++++++++++++++++++++++++++
 + This module defines the concept of Observable.
 +/
module rx.observable;

import std.functional : unaryFun;
import std.range : put, isInputRange, isOutputRange, ElementType;

import rx.disposable;
import rx.observer;
import rx.util;

///Tests if something is a Observable.
template isObservable(T, E)
{
    enum bool isObservable = is(T.ElementType : E) && is(typeof({
                T observable = void;
                Observer!E observer = void;
                auto d = observable.subscribe(observer);
                static assert(isDisposable!(typeof(d)));
            }()));
}
///ditto
template isObservable(TObservable)
{
    enum bool isObservable = __traits(compiles, {
            static assert(isObservable!(TObservable, TObservable.ElementType));
        });

}

///
unittest
{
    struct TestObservable
    {
        alias ElementType = int;

        Disposable subscribe(T)(T observer)
        {
            static assert(isObserver!(T, int));
            return null;
        }
    }

    static assert(isObservable!(TestObservable));
    static assert(isObservable!(TestObservable, int));
    static assert(!isObservable!(TestObservable, Object));
}

///
unittest
{
    static assert(isObservable!(Observable!int));
    static assert(!isObservable!(Observer!int));
    static assert(!isObservable!(string));
    static assert(!isObservable!(Object));
}

///Test if the observer can subscribe to the observable.
template isSubscribable(TObservable, TObserver)
{
    enum bool isSubscribable = is(typeof({
                static assert(isOutputRange!(TObserver, TObservable.ElementType));

                TObservable observable = void;
                TObserver observer = void;
                auto d = observable.subscribe(observer);
                static assert(isDisposable!(typeof(d)));
            }()));
}
///
unittest
{
    struct TestDisposable
    {
        void dispose()
        {
        }
    }

    struct TestObserver
    {
        void put(int n)
        {
        }

        void completed()
        {
        }

        void failure(Exception e)
        {
        }
    }

    struct TestObservable
    {
        alias ElementType = int;

        TestDisposable subscribe(TestObserver observer)
        {
            return TestDisposable();
        }
    }

    static assert(isSubscribable!(TestObservable, TestObserver));
}

///The helper for subscribe easier.
auto doSubscribe(TObservable, E)(auto ref TObservable observable, void delegate(E) doPut,
        void delegate() doCompleted, void delegate(Exception) doFailure)
{
    return doSubscribe(observable, makeObserver(doPut, doCompleted, doFailure));
}
///ditto
auto doSubscribe(TObservable, E)(auto ref TObservable observable,
        void delegate(E) doPut, void delegate() doCompleted)
{
    return doSubscribe(observable, makeObserver(doPut, doCompleted));
}
///ditto
auto doSubscribe(TObservable, E)(auto ref TObservable observable,
        void delegate(E) doPut, void delegate(Exception) doFailure)
{
    return doSubscribe(observable, makeObserver(doPut, doFailure));
}
///ditto
auto doSubscribe(alias f, TObservable)(auto ref TObservable observable)
{
    alias fun = unaryFun!f;
    return doSubscribe(observable, (TObservable.ElementType obj) {
        static if (__traits(compiles, { fun(obj); }))
        {
            fun(obj);
        }
        else
        {
            struct DoSubscribeObserver
            {
                void put(T)(T obj)
                {
                    fun(obj);
                }
            }

            DoSubscribeObserver observer;
            .put(observer, obj);
        }
    });
}
///ditto
auto doSubscribe(TObservable, TObserver)(auto ref TObservable observable, auto ref TObserver observer)
{
    import std.format : format;

    static assert(isObservable!(TObservable, TObservable.ElementType),
            format!"%s is invalid as an Observable"(TObservable.stringof));

    alias ElementType = TObservable.ElementType;
    static if (isSubscribable!(TObservable, TObserver))
        return observable.subscribe(observer);
    else static if (isSubscribable!(TObservable, Observer!ElementType))
        return observable.subscribe(observerObject!ElementType(observer));
    else
    {
        static assert(false, format!"%s can not subscribe '%s', it published by %s"(
                TObserver.stringof, ElementType.stringof, TObservable.stringof));
    }
}
///
unittest
{
    struct TestObservable
    {
        alias ElementType = int;

        auto subscribe(TObserver)(TObserver observer)
        {
            .put(observer, [0, 1, 2]);
            return NopDisposable.instance;
        }
    }

    TestObservable observable;
    int[] result;
    observable.doSubscribe!(n => result ~= n);
    assert(result.length == 3);
}

///
unittest
{
    struct TestObserver
    {
        void put(int n)
        {
        }
    }

    struct TestObservable1
    {
        alias ElementType = int;
        Disposable subscribe(Observer!int observer)
        {
            return null;
        }
    }

    struct TestObservable2
    {
        alias ElementType = int;
        Disposable subscribe(T)(T observer)
        {
            return null;
        }
    }

    TestObservable1 o1;
    auto d0 = o1.doSubscribe((int n) {  }, () {  }, (Exception e) {  });
    auto d1 = o1.doSubscribe((int n) {  }, () {  });
    auto d2 = o1.doSubscribe((int n) {  }, (Exception e) {  });
    auto d3 = o1.doSubscribe((int n) {  });
    auto d4 = o1.doSubscribe(TestObserver());
    TestObservable2 o2;
    auto d5 = o2.doSubscribe((int n) {  }, () {  }, (Exception e) {  });
    auto d6 = o2.doSubscribe((int n) {  }, () {  });
    auto d7 = o2.doSubscribe((int n) {  }, (Exception e) {  });
    auto d8 = o2.doSubscribe((int n) {  });
    auto d9 = o2.doSubscribe(TestObserver());
}

unittest
{
    static struct TestObservable
    {
        alias ElementType = int[];

        Disposable subscribe(TObserver)(TObserver observer)
        {
            .put(observer, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            return null;
        }
    }

    TestObservable observable;

    int sum1 = 0;

    void add(int n)
    {
        sum1 += n;
    }

    observable.doSubscribe!(add); // by value
    assert(sum1 == 55);

    int sum2 = 0;
    observable.doSubscribe!(n => sum2 += n); // by value
    assert(sum2 == 55);

    int size = 0;
    observable.doSubscribe!(arr => size += arr.length); // by array
    assert(size == 10);
}

///Wrapper for Observable objects.
interface Observable(E)
{
    alias ElementType = E;

    Disposable subscribe(Observer!E observer);
}

unittest
{
    static assert(isObservable!(Observable!int, int));
}

unittest
{
    static struct TestNoObservable
    {
        Disposable subscribe(Observer!int observer)
        {
            return null;
        }
    }

    static assert(!isObservable!(TestNoObservable, int));
}

///Class that implements Observable interface and wraps the subscribe method in virtual function.
class ObservableObject(R, E) : Observable!E
{
public:
    this(R observable)
    {
        _observable = observable;
    }

public:
    Disposable subscribe(Observer!E observer)
    {
        return disposableObject(_observable.subscribe(observer));
    }

private:
    R _observable;
}

///Wraps subscribe method in virtual function.
template observableObject(E)
{
    Observable!E observableObject(R)(auto ref R observable)
    {
        static if (is(R : Observable!E))
        {
            return observable;
        }
        else
        {
            return new ObservableObject!(R, E)(observable);
        }
    }
}
///
unittest
{
    int subscribeCount = 0;
    class TestObservable : Observable!int
    {
        Disposable subscribe(Observer!int observer)
        {
            subscribeCount++;
            return NopDisposable.instance;
        }
    }

    auto test = new TestObservable;
    auto observable = observableObject!int(test);
    assert(observable is test);
    assert(subscribeCount == 0);
    auto d = observable.subscribe(null);
    assert(subscribeCount == 1);
}

unittest
{
    int disposeCount = 0;
    int subscribeCount = 0;

    struct TestDisposable
    {
        void dispose()
        {
            disposeCount++;
        }
    }

    struct TestObservable
    {
        TestDisposable subscribe(Observer!int observer)
        {
            subscribeCount++;
            return TestDisposable();
        }
    }

    Observable!int observable = observableObject!int(TestObservable());
    assert(subscribeCount == 0);
    Disposable disposable = observable.subscribe(null);
    assert(subscribeCount == 1);
    assert(disposeCount == 0);
    disposable.dispose();
    assert(disposeCount == 1);
}

//#########################
// Defer
//#########################
private struct DeferObserver(TObserver, E)
{
public:
    this(TObserver observer, EventSignal signal)
    {
        _observer = observer;
        _signal = signal;
    }

public:
    void put(E obj)
    {
        if (_signal.signal)
            return;

        static if (hasFailure!TObserver)
        {
            try
            {
                .put(_observer, obj);
            }
            catch (Exception e)
            {
                _observer.failure(e);
            }
        }
        else
        {
            .put(_observer, obj);
        }
    }

    void completed()
    {
        if (_signal.signal)
            return;
        _signal.setSignal();

        static if (hasCompleted!TObserver)
        {
            _observer.completed();
        }
    }

    void failure(Exception e)
    {
        if (_signal.signal)
            return;
        _signal.setSignal();

        static if (hasFailure!TObserver)
        {
            _observer.failure(e);
        }
    }

private:
    TObserver _observer;
    EventSignal _signal;
}

///Create observable by function that template parameter.
auto defer(E, alias f)()
{
    static struct DeferObservable
    {
        alias ElementType = E;

    public:
        auto subscribe(TObserver)(TObserver observer)
        {
            alias ObserverType = DeferObserver!(TObserver, E);
            alias fun = unaryFun!f;
            auto d = new SignalDisposable;
            static if (__traits(compiles, {
                    auto disposable = fun(ObserverType(observer, d.signal));
                    static assert(isDisposable!(typeof(disposable)));
                }))
            {
                auto subscription = fun(ObserverType(observer, d.signal));
                return new CompositeDisposable(subscription, d);
            }
            else
            {
                fun(ObserverType(observer, d.signal));
                return d;
            }
        }
    }

    return DeferObservable();
}
///
unittest
{
    auto sub = defer!(int, (observer) {
        observer.put(1);
        observer.put(2);
        observer.put(3);
        observer.completed();
    });

    int countPut = 0;
    int countCompleted = 0;
    struct A
    {
        void put(int n)
        {
            countPut++;
        }

        void completed()
        {
            countCompleted++;
        }
    }

    assert(countPut == 0);
    assert(countCompleted == 0);
    auto d = sub.doSubscribe(A());
    assert(countPut == 3);
    assert(countCompleted == 1);
}

unittest
{
    auto sub = defer!(int, (observer) {
        observer.put(0);
        observer.failure(new Exception(""));
        observer.put(1);
    });

    int countPut = 0;
    int countFailure = 0;
    struct A
    {
        void put(int n)
        {
            countPut++;
        }

        void failure(Exception e)
        {
            countFailure++;
        }
    }

    assert(countPut == 0);
    assert(countFailure == 0);
    auto d = sub.doSubscribe(A());
    assert(countPut == 1);
    assert(countFailure == 1);
}

unittest
{
    auto sub = defer!(int, (observer) {
        observer.put(0);
        observer.failure(new Exception(""));
        observer.put(1);
    });

    int countPut = 0;
    struct A
    {
        void put(int n)
        {
            countPut++;
        }
    }

    assert(countPut == 0);
    auto d = sub.doSubscribe(A());
    assert(countPut == 1);
}

unittest
{
    Disposable subscribeImpl(Observer!int observer)
    {
        .put(observer, 1);
        return null;
    }

    import std.array : appender;

    auto buf = appender!(int[]);

    auto put1 = defer!int(&subscribeImpl);
    auto d = put1.subscribe(buf);

    assert(buf.data.length == 1);
    assert(buf.data[0] == 1);
    assert(d !is null);
}

unittest
{
    auto sub = defer!(int, (observer) {
        observer.put(1);
        return NopDisposable.instance;
    });

    auto called = false;
    sub.doSubscribe((int _) { called = true; });
    assert(called);
}

auto defer(E, TSubscribe)(auto ref TSubscribe subscribeImpl)
{
    struct DeferObservable
    {
        alias ElementType = E;

        TSubscribe _subscribeImpl;

        this(ref TSubscribe subscribeImpl)
        {
            _subscribeImpl = subscribeImpl;
        }

        auto subscribe(TObserver)(auto ref TObserver observer)
        {
            alias ObserverType = DeferObserver!(TObserver, E);

            auto cancel = new SignalDisposable;
            static if (__traits(compiles, {
                    auto d = _subscribeImpl(ObserverType.init);
                    static assert(isDisposable!(typeof(d)));
                }))
            {
                auto subscription = disposableObject(_subscribeImpl(ObserverType(observer,
                        cancel.signal)));
                return new CompositeDisposable(cancel, subscription);
            }
            else static if (__traits(compiles, {
                    _subscribeImpl(ObserverType.init);
                }))
            {
                _subscribeImpl(ObserverType(observer, cancel.signal));
                return cancel;
            }
            else static if (__traits(compiles, {
                    auto d = _subscribeImpl(Observer!E.init);
                    static assert(isDisposable!(typeof(d)));
                }))
            {
                auto subscription = _subscribeImpl(observerObject!E(ObserverType(observer,
                        cancel.signal)));
                return new CompositeDisposable(cancel, subscription);
            }
            else static if (__traits(compiles, {
                    _subscribeImpl(Observer!E.init);
                }))
            {
                _subscribeImpl(observerObject!E(ObserverType(observer, cancel.signal)));
                return cancel;
            }
            else
            {
                static assert(false);
            }
        }
    }

    return DeferObservable(subscribeImpl);
}

unittest
{
    import std.array : appender;

    auto buf = appender!(int[]);

    auto put12 = defer!int((Observer!int observer) {
        .put(observer, 1);
        .put(observer, 2);
        return NopDisposable.instance;
    });
    auto d = put12.subscribe(buf);

    assert(buf.data.length == 2);
    assert(buf.data[0] == 1);
    assert(buf.data[1] == 2);
}

unittest
{
    int last = 0;
    struct TestObserver
    {
        void put(int n)
        {
            last = n;
        }
    }

    auto disposed1 = false;
    auto sub1 = defer!int((Observer!int observer) {
        observer.put(1);
        return new AnonymouseDisposable({ disposed1 = true; });
    });

    auto sub2 = defer!int((Observer!int observer) { observer.put(100); });

    TestObserver observer;
    last = 0;
    auto disposable1 = sub1.subscribe(observer);
    assert(last == 1);
    assert(!disposed1);
    disposable1.dispose();
    assert(disposed1);

    last = 0;
    auto disposable2 = sub2.subscribe(observer);
    assert(last == 100);
    disposable2.dispose();
}

unittest
{
    size_t hasBeenCalled1 = 0;
    struct SubscribeImpl1
    {
        Disposable opCall(TObserver)(TObserver observer)
        {
            hasBeenCalled1++;
            return NopDisposable.instance;
        }
    }

    size_t hasBeenCalled2 = 0;
    struct SubscribeImpl2
    {
        void opCall(TObserver)(TObserver observer)
        {
            hasBeenCalled2++;
        }
    }

    struct TestObserver
    {
        void put(int _)
        {
        }
    }

    SubscribeImpl1 impl1;
    auto sub1 = defer!int(impl1);

    assert(hasBeenCalled1 == 0);
    auto disposable1 = sub1.subscribe(TestObserver());
    assert(hasBeenCalled1 == 1);
    disposable1.dispose();

    SubscribeImpl2 impl2;
    auto sub2 = defer!int(impl2);

    assert(hasBeenCalled2 == 0);
    auto disposable2 = sub2.subscribe(TestObserver());
    assert(hasBeenCalled2 == 1);
    disposable2.dispose();
}

unittest
{
    class SubscribeImpl1
    {
    public:
        void publish()
        {
            .put(_observer, 1);
        }

    public:
        Disposable opCall(TObserver)(TObserver observer)
        {
            _observer = observerObject!int(observer);
            return NopDisposable.instance;
        }

    private:
        Observer!int _observer;
    }

    import rx.subject : CounterObserver;

    auto observer1 = new CounterObserver!int;
    auto impl1 = new SubscribeImpl1;
    auto sub1 = defer!int(impl1);
    auto disposable1 = sub1.subscribe(observer1);
    disposable1.dispose();

    assert(observer1.putCount == 0);
    impl1.publish();
    assert(observer1.putCount == 0);

    auto observer2 = new CounterObserver!int;
    auto impl2 = new SubscribeImpl1;
    auto sub2 = defer!int(impl2);
    auto disposable2 = sub2.subscribe(observer2);
    assert(observer2.putCount == 0);
    impl2.publish();
    assert(observer2.putCount == 1);
    disposable2.dispose();
    impl2.publish();
    assert(observer2.putCount == 1);
}

///
auto empty(E)()
{
    static struct EmptyObservable
    {
        alias ElementType = E;

        Disposable subscribe(TObserver)(auto ref TObserver observer)
        {
            static if (hasCompleted!TObserver)
            {
                observer.completed();
            }
            return NopDisposable.instance;
        }
    }

    return EmptyObservable();
}

unittest
{
    auto completed = false;
    auto o = empty!int();

    assert(!completed);
    auto d = o.doSubscribe((int n) {  }, () { completed = true; });
    assert(completed);
}

///
auto never(E)()
{
    static struct NeverObservable
    {
        alias ElementType = E;

        Disposable subscribe(TObserver)(auto ref TObserver observer)
        {
            return NopDisposable.instance;
        }
    }

    return NeverObservable();
}

unittest
{
    auto o = never!int();
    auto d = o.doSubscribe((int) {  });
    d.dispose();
}

///
auto error(E)(auto ref Exception e)
{
    static struct ErrorObservable
    {
        alias ElementType = E;

        Exception _e;

        this(ref Exception e)
        {
            _e = e;
        }

        Disposable subscribe(TObserver)(auto ref TObserver observer)
        {
            static if (hasFailure!TObserver)
            {
                observer.failure(_e);
            }
            return NopDisposable.instance;
        }
    }

    return ErrorObservable(e);
}

unittest
{
    auto expected = new Exception("TEST");
    auto o = error!int(expected);

    Exception actual = null;
    o.doSubscribe((int n) {  }, (Exception e) { actual = e; });
    assert(actual is expected);
}

///
auto from(R)(auto ref R input) if (isInputRange!R)
{
    alias E = ElementType!R;

    static struct FromObservable
    {
        alias ElementType = E;

        this(ref R input)
        {
            this.input = input;
        }

        Disposable subscribe(TObserver)(auto ref TObserver observer)
                if (isOutputRange!(TObserver, ElementType))
        {
            .put(observer, input);
            return NopDisposable.instance;
        }

        R input;
    }

    return FromObservable(input);
}
///
alias asObservable = from;

///
unittest
{
    import std.range : iota;

    auto obs = from(iota(10));
    auto res = new int[10];
    auto d = obs.subscribe(res[]);
    scope (exit)
        d.dispose();

    assert(res.length == 10);
    assert(res[0] == 0);
    assert(res[9] == 9);
}

///
unittest
{
    import std.range : iota;

    auto obs = iota(10).asObservable();
    auto res = new int[10];
    auto d = obs.subscribe(res[]);
    scope (exit)
        d.dispose();

    assert(res.length == 10);
    assert(res[0] == 0);
    assert(res[9] == 9);
}
