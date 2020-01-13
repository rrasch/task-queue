require_relative './cmd'

class Util

  def initialize(args)
    @cmd = Cmd.new(args)
  end

  def ping
    @cmd.do_cmd("ping -c1 -W1 wwww.google.com")
  end

  def forture
    @cmd.do_cmd("fortune")
  end

end

