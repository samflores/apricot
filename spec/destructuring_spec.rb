describe 'Destructuring' do
  include CompilerSpec

  it 'destructures simple arrays in let and loop forms' do
    apr('(let [[a b] [1 2]] [b a])').should == [2, 1]
    apr('(let [[a b c] [1 2]] c)').should be_nil
    apr('(loop [[a b] [1 2]] [b a])').should == [2, 1]
    apr('(loop [[a b c] [1 2]] c)').should be_nil
  end

  it 'destructures arrays with & in let and loop forms' do
    apr('(let [[a b & c] [1 2 3 4]] c)').should == [3, 4]
    apr('(let [[a b & c] [1 2]] c)').should be_nil
    apr('(loop [[a b & c] [1 2 3 4]] c)').should == [3, 4]
    apr('(loop [[a b & c] [1 2]] c)').should be_nil
  end

  it 'destructures arrays with :as form in let and loop forms' do
    apr('(let [[a b :as c] [1 2 3 4]] c)').should == [1, 2, 3, 4]
    apr('(loop [[a b :as c] [1 2 3 4]] c)').should == [1, 2, 3, 4]
  end

  it 'destructures nested arrays in let and loop forms' do
    apr('(let [[[a b c] [d e f]] [[1 2] [3 4 5]]] [f e d c b a])').should == [5, 4, 3, nil, 2, 1]
    apr('(loop [[[a b c] [d e f]] [[1 2] [3 4 5]]] [f e d c b a])').should == [5, 4, 3, nil, 2, 1]
  end

  it 'mixes up all destructuring types is let and loop forms' do
    apr('(let [[[a b] & c :as d] [[1 2] 3 4]] c)').should == [3, 4]
    apr('(let [[[a b] & c :as d] [[1 2] 3 4]] d)').should == [[1, 2], 3, 4]
    apr('(loop [[[a b] & c :as d] [[1 2] 3 4]] c)').should == [3, 4]
    apr('(loop [[[a b] & c :as d] [[1 2] 3 4]] d)').should == [[1, 2], 3, 4]
  end

  it 'destructures simple hashs in let and loop forms' do
    apr('(let [{a :a b :b} {:a 1 :b 2}] [b a])').should == [2, 1]
    apr('(let [{a :a b :b c :c} {:a 1 :b 2}] c)').should be_nil
    apr('(loop [{a :a b :b} {:a 1 :b 2}] [b a])').should == [2, 1]
    apr('(loop [{a :a b :b c :c} {:a 1 :b 2}] c)').should be_nil
  end

  it 'destructures hashs with :as form in let and loop forms' do
    apr('(let [{a :a b :b :as c} {:a 1 :b 2}] c)').should == {a: 1, b: 2}
    apr('(loop [{a :a b :b :as c} {:a 1 :b 2}] c)').should == {a: 1, b: 2}
  end

  it 'destructures hashs with :or form in let and loop forms' do
    apr('(let [{a :a b :b c :c :or {a 2 b 3}} {:a 5 :c 6}] [a b c])').should == [5, 3, 6]
    apr('(loop [{a :a b :b c :c :or {a 2 b 3}} {:a 5 :c 6}] [a b c])').should == [5, 3, 6]
  end

  it 'destructures hashs using :keys form in let and loop forms' do
    apr('(let  [{:keys [a b c]} {:a 2 :b 4 :c 8}] [c b a])').should == [8, 4, 2]
  end
end

