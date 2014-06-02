class Bagit
 
  attr :bag_dir
  attr :bagit_tool
 
  def initialize(bag_dir = ".")
    @bag_dir = bag_dir
    @bagit_tool = `which bag`.strip
  end
 
  def validate?
    system @bagit_tool, 'verifyvalid', @bag_dir
    $?.success?
  end

end

