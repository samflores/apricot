describe 'Apricot' do
  include CompilerSpec

  it 'compiles fn forms' do
    apr('((fn []))').should == nil
    apr('((fn [] 42))').should == 42
    apr('((fn [x] x) 42)').should == 42
    apr('((fn [x y] [y x]) 1 2)').should == [2, 1]
  end

  it 'compiles fn forms with optional arguments' do
    apr('((fn [[x 42]] x))').should == 42
    apr('((fn [[x 42]] x) 0)').should == 0
    apr('((fn [x [y 2]] [x y]) 1)').should == [1, 2]
    apr('((fn [x [y 2]] [x y]) 3 4)').should == [3, 4]
    apr('((fn [[x 1] [y 2]] [x y]))').should == [1, 2]
    apr('((fn [[x 1] [y 2]] [x y]) 3)').should == [3, 2]
    apr('((fn [[x 1] [y 2]] [x y]) 3 4)').should == [3, 4]
  end

  it 'compiles fn forms with splat arguments' do
    apr('((fn [& x] x))').should == []
    apr('((fn [& x] x) 1)').should == [1]
    apr('((fn [& x] x) 1 2)').should == [1, 2]
    apr('((fn [x & y] y) 1)').should == []
    apr('((fn [x & y] y) 1 2 3)').should == [2, 3]
  end

  it 'compiles fn forms with optional and splat arguments' do
    apr('((fn [x [y 2] & z] [x y z]) 1)').should == [1, 2, []]
    apr('((fn [x [y 2] & z] [x y z]) 1 3)').should == [1, 3, []]
    apr('((fn [x [y 2] & z] [x y z]) 1 3 4 5)').should == [1, 3, [4, 5]]
  end

  it 'compiles fn forms with block arguments' do
    apr('((fn [| block] block))').should == nil
    apr('(.call (fn [| block] (block)) | (fn [] 42))').should == 42

    fn = apr '(fn [x | block] (block x))'
    # Without passing a block, 'block' is nil.
    expect { fn.call(2) }.to raise_error(NoMethodError)
    fn.call(2) {|x| x + 40 }.should == 42

    reduce_args = apr <<-CODE
      (fn reduce-args
        ([x] x)
        ([x y | f] (f x y))
        ([x y & more | f]
         (if (seq more)
           (recur (f x y) (first more) (next more) f)
           (f x y))))
    CODE

    reduce_args.call(1).should == 1
    reduce_args.call(40, 2) {|x,y| x * y }.should == 80
    reduce_args.call(1,2,3,4,5,6) {|x,y| x + y }.should == 21
  end

  it 'does not compile invalid fn forms' do
    bad_apr '(fn :foo)'
    bad_apr '(fn [1])'
    bad_apr '(fn [[x 1] y])'
    bad_apr '(fn [[1 1]])'
    bad_apr '(fn [[x]])'
    bad_apr '(fn [&])'
    bad_apr '(fn [& x y])'
    bad_apr '(fn [x x])'
    bad_apr '(fn [x & rest1 & rest2])'
    bad_apr '(fn [a b x c d x e f])'
    bad_apr '(fn [a x b [x 1]])'
    bad_apr '(fn [a b x c d & x])'
    bad_apr '(fn [a b c [x 1] [y 2] [x 3]])'
    bad_apr '(fn [a b [x 1] & x])'
    bad_apr '(fn [|])'
    bad_apr '(fn [| &])'
    bad_apr '(fn [| & a])'
    bad_apr '(fn [| a &])'
    bad_apr '(fn [& x |])'
    bad_apr '(fn [| x y])'
    bad_apr '(fn [| x & y])'
    bad_apr '(fn [x | x])'
    bad_apr '(fn [x | b1 | b2])'
  end

  it 'compiles arity-overloaded fn forms' do
    apr('((fn ([] 0)))').should == 0
    apr('((fn ([x] x)) 42)').should == 42
    apr('((fn ([[x 42]] x)))').should == 42
    apr('((fn ([& rest] rest)) 1 2 3)').should == [1, 2, 3]
    apr('((fn ([] 0) ([x] x)))').should == 0
    apr('((fn ([] 0) ([x] x)) 42)').should == 42
    apr('((fn ([x] x) ([x y] y)) 42)').should == 42
    apr('((fn ([x] x) ([x y] y)) 42 13)').should == 13
    apr('((fn ([x] x) ([x y & z] z)) 1 2 3 4)').should == [3, 4]

    add_fn = apr <<-CODE
      (fn
        ([] 0)
        ([x] x)
        ([x y] (.+ x y))
        ([x y & more]
         (.reduce more (.+ x y) :+)))
    CODE

    add_fn.call.should == 0
    add_fn.call(42).should == 42
    add_fn.call(1,2).should == 3
    add_fn.call(1,2,3).should == 6
    add_fn.call(1,2,3,4,5,6,7,8).should == 36

    two_or_three = apr '(fn ([x y] 2) ([x y z] 3))'
    expect { two_or_three.call }.to raise_error(ArgumentError)
    expect { two_or_three.call(1) }.to raise_error(ArgumentError)
    two_or_three.call(1,2).should == 2
    two_or_three.call(1,2,3).should == 3
    expect { two_or_three.call(1,2,3,4) }.to raise_error(ArgumentError)
    expect { two_or_three.call(1,2,3,4,5) }.to raise_error(ArgumentError)
  end

  it 'compiles arity-overloaded fns with no matching overloads for some arities' do
    zero_or_two = apr '(fn ([] 0) ([x y] 2))'
    zero_or_two.call.should == 0
    expect { zero_or_two.call(1) }.to raise_error(ArgumentError)
    zero_or_two.call(1,2).should == 2
    expect { zero_or_two.call(1,2,3) }.to raise_error(ArgumentError)

    one_or_four = apr '(fn ([w] 1) ([w x y z] 4))'
    expect { one_or_four.call }.to raise_error(ArgumentError)
    one_or_four.call(1).should == 1
    expect { one_or_four.call(1,2) }.to raise_error(ArgumentError)
    expect { one_or_four.call(1,2,3) }.to raise_error(ArgumentError)
    one_or_four.call(1,2,3,4).should == 4
    expect { one_or_four.call(1,2,3,4,5) }.to raise_error(ArgumentError)
  end

  it 'does not compile invalid arity-overloaded fn forms' do
    bad_apr '(fn ([] 1) :foo)'
    bad_apr '(fn ([] 1) ([] 2))'
    bad_apr '(fn ([[o 1]] 1) ([] 2))'
    bad_apr '(fn ([] 1) ([[o 2]] 2))'
    bad_apr '(fn ([[o 1]] 1) ([[o 2]] 2))'
    bad_apr '(fn ([x [o 1]] 1) ([x] 2))'
    bad_apr '(fn ([x [o 1]] 1) ([[o 2]] 2))'
    bad_apr '(fn ([x y z [o 1]] 1) ([x y z & rest] 2))'
    bad_apr '(fn ([x [o 1] [p 2] [q 3]] 1) ([x y z] 2))'
    bad_apr '(fn ([x & rest] 1) ([x y] 2))'
    bad_apr '(fn ([x & rest] 1) ([x [o 1]] 2))'
    bad_apr '(fn ([x [o 1] & rest] 1) ([x] 2))'
    bad_apr '(fn ([[x 1] [y 2]] 3) ([x & y] 4))'
  end

  it 'compiles fn forms with self-reference' do
    foo = apr '(fn foo [] foo)'
    foo.call.should == foo

    # This one will stack overflow from the infinite loop.
    expect { apr '((fn foo [] (foo)))' }.to raise_error(SystemStackError)

    add = apr <<-CODE
      (fn add
        ([] 0)
        ([& args]
         (.+ (first args) (apply add (rest args)))))
    CODE

    add.call.should == 0
    add.call(1).should == 1
    add.call(1,2,3).should == 6
  end

  it 'compiles recur forms in fns' do
    apr(<<-CODE).should == 15
      ((fn [x y]
         (if (. x > 0)
           (recur (. x - 1) (. y + x))
           y))
       5 0)
    CODE
  end

  it 'compiles recur forms in fns with optional arguments' do
    apr(<<-CODE).should == 150
      ((fn [x y [mult 10]]
         (if (. x > 0)
           (recur (. x - 1) (. y + x) mult)
           (* y mult)))
       5 0)
    CODE

    apr(<<-CODE).should == 300
      ((fn [x y [mult 10]]
         (if (. x > 0)
           (recur (. x - 1) (. y + x) mult)
           (* y mult)))
       5 0 20)
    CODE
  end

end
