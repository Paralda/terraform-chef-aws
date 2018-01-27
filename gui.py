from Tkinter import *

#Checkbox variables
#Provider
provider="""\
provider "aws" {
region = "us-east-1"
}"""

#VPC, route table, and external route
vpc="""\
resource "aws_vpc" "chef-vpc" {
    cidr_block = "172.17.0.0/16"
    tags {
    Name = "chef-vpc"
    }
}

resource "aws_route_table" "external" {
  count = 1
  vpc_id = "${aws_vpc.chef-vpc.id}"

  tags {
    Name = "routetable"
  }
}

resource "aws_route" "external" {
  route_table_id         = "${aws_route_table.external.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}"""

#Subnet and route table association in us-east-1b
subnet1b="""\
resource "aws_subnet" "site-main" {
    vpc_id = "${aws_vpc.chef-vpc.id}"
    cidr_block = "172.17.10.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags {
        Name = "site-main"
    }
}

resource "aws_route_table_association" "external-main" {
  count          = 2
  subnet_id      = "${aws_subnet.site-main.id}"
  route_table_id = "${aws_route_table.external.id}"
}"""

#Subnet and route table association in us-east-1d
subnet1d="""\
#Subnet 1d
resource "aws_subnet" "site-secondary" {
    vpc_id = "${aws_vpc.chef-vpc.id}"
    cidr_block = "172.17.20.0/24"
    availability_zone = "us-east-1d"
    map_public_ip_on_launch = true
    tags {
        Name = "site-secondary"
    }
}

resource "aws_route_table_association" "external-secondary" {
  count          = 2
  subnet_id      = "${aws_subnet.site-secondary.id}"
  route_table_id = "${aws_route_table.external.id}"
}
"""

#Allow_all security group (associated with VPC created above)
allow-all-sec="""\
resource "aws_security_group" "allow_all" {
name = "allow_all"
description = "Allow inbound SSH and HTTP traffic"
vpc_id = "${aws_vpc.chef-vpc.id}"

ingress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
}

egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
}

tags {
Name = "allow_all"
}
}"""

#Webserver in us-east-1b
webserver1b="""\
resource "aws_instance" "webserver-main" {
provisioner "chef" {
server_url = "https://chef.willbennett.tech/organizations/test/"
user_name = "paralda"
user_key = "${file("C:\\Users\\willb\\terraform-chef-aws\\.chef\\paralda.pem")}"
node_name = "webserver-main"
recreate_client = true
ssl_verify_mode = ":verify_none"
run_list = [ "webserver", "webserver::php", "webserver::site1" ]
connection {
host = "${self.public_ip}"    
user = "centos"
private_key = "${file("C:\\Users\\willb\\chef.pem")}"
agent = false
}
}
instance_type = "t2.micro"
associate_public_ip_address = true
ami = "ami-4bf3d731"
key_name = "chef"
subnet_id = "${aws_subnet.site-main.id}"
security_groups = [ "${aws_security_group.allow_all.id}"]
}"""

#Webserver in us-east-1d
webserver1d="""\
resource "aws_instance" "webserver-secondary" {
provisioner "chef" {
server_url = "https://chef.willbennett.tech/organizations/test/"
user_name = "paralda"
user_key = "${file("C:\\Users\\willb\\terraform-chef-aws\\.chef\\paralda.pem")}"
node_name = "webserver-secondary"
recreate_client = true
ssl_verify_mode = ":verify_none"
run_list = [ "webserver", "webserver::php", "webserver::site2" ]
connection {
host = "${self.public_ip}"   
user = "centos"
private_key = "${file("C:\\Users\\willb\\chef.pem")}"
agent = false
}
}
instance_type = "t2.micro"
associate_public_ip_address = true
ami = "ami-4bf3d731"
key_name = "chef"
subnet_id = "${aws_subnet.site-secondary.id}"
security_groups = [ "${aws_security_group.allow_all.id}"]
}"""

#RDS Subnet
rdssubnet="""\
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = ["${aws_subnet.site-main.id}", "${aws_subnet.site-secondary.id}"]

  tags {
    Name = "db_subnet_group"
  }
}"""

#RDS Instance (using securitygroup allow_all)
rdsinstance="""\
resource "aws_db_instance" "chefsql" {
  allocated_storage    = 10
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.6.37"
  instance_class       = "db.t2.micro"
  name                 = "chefsql"
  username             = "chef"
  password             = "chefpass"
  db_subnet_group_name = "${aws_db_subnet_group.db_subnet_group.id}"
  vpc_security_group_ids = [ "${aws_security_group.allow_all.id}" ]
  parameter_group_name = "default.mysql5.6"
}"""

#RDS Route53 Record
rdsroute53="""\
resource "aws_route53_record" "rds" {
    zone_id = "Z19Z5BHTE12ISK"
    name = "rds.willbennett.tech"
    type = "CNAME"
    ttl = "300"
    records = ["${aws_db_instance.chefsql.endpoint}"]
}"""

#Load-Balancer Setup (requires both webservers and subnets)
loadbalancer="""\
#Target Group
resource "aws_lb_target_group" "httpdtarget" {
    name = "httpdtarget"
    port = "80"
    protocol = "TCP"
    vpc_id = "${aws_vpc.chef-vpc.id}"
}

#Listener
resource "aws_lb_listener" "httpdlisten" {
    load_balancer_arn = "${aws_lb.test.arn}"
    port = "80"
    protocol = "TCP"

    default_action {
        target_group_arn = "${aws_lb_target_group.httpdtarget.arn}"
        type = "forward"
    }
}

#Target Attachment
resource "aws_lb_target_group_attachment" "httpattachment-main" {
    target_group_arn = "${aws_lb_target_group.httpdtarget.arn}"
    target_id = "${aws_instance.webserver-main.id}"    
    port = 80
}

resource "aws_lb_target_group_attachment" "httpattachment-secondary" {
    target_group_arn = "${aws_lb_target_group.httpdtarget.arn}"
    target_id = "${aws_instance.webserver-secondary.id}"  
    port = 80
}"""

class Checkbar(Frame):
   def __init__(self, parent=None, picks=[], side=LEFT, anchor=W):
      Frame.__init__(self, parent)
      self.vars = []
      for pick in picks:
         var = IntVar()
         chk = Checkbutton(self, text=pick, variable=var)
         chk.pack(side=side, anchor=anchor, expand=YES)
         self.vars.append(var)
   def state(self):
      return map((lambda var: var.get()), self.vars)
if __name__ == '__main__':
   root = Tk()
   lng = Checkbar(root, ['Python', 'Ruby', 'Perl', 'C++'])
   tgl = Checkbar(root, ['English','German'])
   lng.pack(side=TOP,  fill=X)
   tgl.pack(side=LEFT)
   lng.config(relief=GROOVE, bd=2)

   def allstates(): 
      print(list(lng.state()), list(tgl.state()))
   Button(root, text='Quit', command=root.quit).pack(side=RIGHT)
   Button(root, text='Peek', command=allstates).pack(side=RIGHT)
   root.mainloop()