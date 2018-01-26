provider "aws" {
region = "us-east-1"
}

#VPC
resource "aws_vpc" "chef-vpc" {
    cidr_block = "172.17.0.0/16"
    tags {
    Name = "chef-vpc"
    }
}

#Subnet 1b
resource "aws_subnet" "site-main" {
    vpc_id = "${aws_vpc.chef-vpc.id}"
    cidr_block = "172.17.10.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags {
        Name = "site-main"
    }
}

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

#Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.chef-vpc.id}"
    tags {
        Name = "gw"
    }
}

## Route Table
resource "aws_route_table" "external" {
  count = 1
  vpc_id = "${aws_vpc.chef-vpc.id}"

  tags {
    Name = "routetable"
  }
}

#External Route
resource "aws_route" "external" {
  route_table_id         = "${aws_route_table.external.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

resource "aws_route_table_association" "external-main" {
  count          = 2
  subnet_id      = "${aws_subnet.site-main.id}"
  #subnets         = ["${aws_subnet.site-main.id}", "${aws_subnet.site-secondary.id}"]
  route_table_id = "${aws_route_table.external.id}"
}

resource "aws_route_table_association" "external-secondary" {
  count          = 2
  subnet_id      = "${aws_subnet.site-secondary.id}"
  #subnets         = ["${aws_subnet.site-main.id}", "${aws_subnet.site-secondary.id}"]
  route_table_id = "${aws_route_table.external.id}"
}



#Security Group
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
}

#Webserver 1
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
#vpc_id = "${aws_vpc.chef-vpc.id}"
subnet_id = "${aws_subnet.site-main.id}"
security_groups = [ "${aws_security_group.allow_all.id}"]
}

#Webserver 2
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
#vpc_id = "${aws_vpc.chef-vpc.id}"
subnet_id = "${aws_subnet.site-secondary.id}"
security_groups = [ "${aws_security_group.allow_all.id}"]
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = ["${aws_subnet.site-main.id}", "${aws_subnet.site-secondary.id}"]

  tags {
    Name = "db_subnet_group"
  }
}

#RDS Instance
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
}

#RDS DNS
resource "aws_route53_record" "rds" {
    zone_id = "Z19Z5BHTE12ISK"
    name = "rds.willbennett.tech"
    type = "CNAME"
    ttl = "300"
    records = ["${aws_db_instance.chefsql.endpoint}"]
}

# #RDS Security Group

# resource "aws_db_security_group" "chefrdssec" {
#     name = "chefrdssec"

#     ingress {
#     from_port = 0
#     to_port = 0
#     protocol = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
# }
# }

#ELB
resource "aws_lb" "test" {
  name            = "test-lb-tf"
  internal        = false
  #security_groups = ["allow_all"]
  subnets         = ["${aws_subnet.site-main.id}", "${aws_subnet.site-secondary.id}"]
  load_balancer_type = "network"
 tags {
    Environment = "production"
  }
}

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
}
