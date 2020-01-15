require_relative './cmd'

class Util

  def initialize(args)
    @cmd = Cmd.new(args)
  end

  def ping
    @cmd.do_cmd("ping -c1 -W1 www.google.com")
  end

  def fortune
    @cmd.do_cmd("fortune")
  end

  def nope
    @cmd.do_cmd("false")
  end

end

