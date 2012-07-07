describe Apricot::Parser do
  def parse(s)
    @ast = described_class.new(s).parse
    @first = @ast.first
    @ast
  end

  it 'parses nothing' do
    parse('').should be_empty
  end

  it 'skips whitespace' do
    parse(" \n\t,").should be_empty
  end

  it 'skips comments' do
    parse('; example').should be_empty
  end

  it 'parses identifiers' do
    parse('example').length.should == 1
    @first.should be_a(Apricot::AST::Identifier)
    @first.value.should == 'example'
  end

  it 'parses integers' do
    parse('123').length.should == 1
    @first.should be_a(Apricot::AST::Integer)
    @first.value.should == 123
  end

  it 'parses radix integers' do
    parse('2r10').length.should == 1
    @first.should be_a(Apricot::AST::Integer)
    @first.value.should == 2
  end

  it 'parses floats' do
    parse('1.23').length.should == 1
    @first.should be_a(Apricot::AST::Float)
    @first.value.should == 1.23
  end

  it 'parses rationals' do
    parse('12/34').length.should == 1
    @first.should be_a(Apricot::AST::Rational)
    @first.numerator.should == 12
    @first.denominator.should == 34
  end

  it 'does not parse invalid numbers' do
    expect { parse('12abc') }.to raise_error(Apricot::Parser::ParseError)
  end

  it 'parses symbols' do
    parse(':example').length.should == 1
    @first.should be_a(Apricot::AST::Symbol)
    @first.value.should == 'example'
  end

  it 'does not parse empty symbols' do
    expect { parse(':') }.to raise_error(Apricot::Parser::ParseError)
  end

  it 'parses empty lists' do
    parse('()').length.should == 1
    @first.should be_a(Apricot::AST::List)
    @first.value.should be_empty
  end

  it 'parses lists' do
    parse('(1 two)').length.should == 1
    @first.should be_a(Apricot::AST::List)
    @first.value[0].should be_a(Apricot::AST::Integer)
    @first.value[1].should be_a(Apricot::AST::Identifier)
  end

  it 'parses empty arrays' do
    parse('[]').length.should == 1
    @first.should be_a(Apricot::AST::Array)
    @first.value.should be_empty
  end

  it 'parses arrays' do
    parse('[1 two]').length.should == 1
    @first.should be_a(Apricot::AST::Array)
    @first.value[0].should be_a(Apricot::AST::Integer)
    @first.value[1].should be_a(Apricot::AST::Identifier)
  end

  it 'parses empty hashes' do
    parse('{}').length.should == 1
    @first.should be_a(Apricot::AST::Hash)
    @first.value.should be_empty
  end

  it 'parses hashes' do
    parse('{:example 1}').length.should == 1
    @first.should be_a(Apricot::AST::Hash)
    @first.value.length.should == 1
    key = @first.value.keys.first
    key.should be_a(Apricot::AST::Symbol)
    @first.value[key].should be_a(Apricot::AST::Integer)
  end

  it 'does not parse invalid hashes' do
    expect { parse('{:foo 1 :bar}') }.to raise_error(Apricot::Parser::ParseError)
  end

  it 'parses multiple forms' do
    parse('foo bar').length.should == 2
    @ast[0].should be_a(Apricot::AST::Identifier)
    @ast[1].should be_a(Apricot::AST::Identifier)
  end
end
