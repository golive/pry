class Pry

  attr_accessor :input, :output
  attr_accessor :commands
  attr_accessor :default_prompt, :wait_prompt
  
  def initialize(options={})

    options = {
      :input => Pry.input,
      :output => Pry.output,
      :commands => Pry.commands,
      :default_prompt => Pry.default_prompt,
      :wait_prompt => Pry.wait_prompt
    }.merge!(options)
    
    @input = options[:input]
    @output = options[:output]
    @commands = options[:commands]
    @default_prompt = options[:default_prompt]
    @wait_prompt = options[:wait_prompt]
  end

  def nesting
    self.class.nesting
  end

  def nesting=(v)
    self.class.nesting = v
  end
  
  # loop
  def repl(target=TOPLEVEL_BINDING)
    target = binding_for(target)
    target_self = target.eval('self')
    output.session_start(target_self)

    nesting_level = nesting.size

    # Make sure _ exists
    target.eval("_ = Pry.last_result")
    
    break_level = catch(:breakout) do
      nesting << [nesting.size, target_self]
      loop do
        rep(target) 
      end
    end

    nesting.pop
    output.session_end(target_self)

    # we only enter here if :breakout has been thrown
    if nesting_level != break_level
      throw :breakout, break_level 
    end
    
    target_self
  end
  
  # print
  def rep(target=TOPLEVEL_BINDING)
    target = binding_for(target)
    output.print re(target)
  end

  # eval
  def re(target=TOPLEVEL_BINDING)
    target = binding_for(target)
    Pry.last_result = target.eval r(target)
    target.eval("_ = Pry.last_result")
  rescue SystemExit => e
    exit
  rescue Exception => e
    e
  end

  # read
  def r(target=TOPLEVEL_BINDING)
    target = binding_for(target)
    eval_string = ""
    loop do
      val = input.read(prompt(eval_string, target, nesting.level))
      eval_string << "#{val.chomp}\n"
      process_commands(val, eval_string, target)
      
      break eval_string if valid_expression?(eval_string)
    end
  end
  
  def process_commands(val, eval_string, target)
    def eval_string.clear() replace("") end

    pattern, action = commands.find { |k, v| Array(k).any? { |a| a === val } }

    if pattern
      options = {
        :captures => $~ ? $~.captures : nil,
        :eval_string => eval_string,
        :target => target,
        :val => val,
        :nesting => nesting,
        :output => output
      }

      action.call(options)
    end
  end

  def prompt(eval_string, target, nest)
    target_self = target.eval('self')
    
    if eval_string.empty?
      default_prompt.call(target_self, nest)
    else
      wait_prompt.call(target_self, nest)
    end
  end

  if RUBY_VERSION =~ /1.9/
    require 'ripper'
    
    def valid_expression?(code)
      !!Ripper::SexpBuilder.new(code).parse
    end
    
  else
    require 'ruby_parser'
    
    def valid_expression?(code)
      RubyParser.new.parse(code)
    rescue Racc::ParseError, SyntaxError
      false
    else
      true
    end
  end

  def binding_for(target)
    if target.is_a?(Binding)
      target
    else
      if target == TOPLEVEL_BINDING.eval('self')
        TOPLEVEL_BINDING
      else
        target.__binding__
      end
    end
  end
end