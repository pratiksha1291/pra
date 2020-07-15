provider "aws" {
  region     = "ap-south-1"
  profile = "lwprofile"

}
resource "tls_private_key" "terra_pri_task2" { 
  algorithm   = "RSA"
  rsa_bits = "2048"
}


resource "aws_key_pair" "terra_task2" {
  depends_on = [ tls_private_key.terra_pri_task2, ]
  key_name   = "terra_task2"
  public_key = tls_private_key.terra_pri_task2.public_key_openssh
}

resource "aws_security_group" "allow_http_NFS" {
  name        = "allow_http"
  description = "Allows http and ssh NFS"
  vpc_id      = "vpc-5d978a35"

  ingress {
    description = "HTTP allow"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
}
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "allow_HTTP"
  }
}

resource "aws_s3_bucket" "prattask2terra" {
  bucket = "buckettaskterra"
  force_destroy = true
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "MYBUCKETPOLICY",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::buckettaskterra/*"
    }
  ]
}
POLICY
    
}



resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.prattask2terra.id
  key    = "IMG_20181027_212043_938.jpg"
  source = "C:/Users/Prat/Desktop/IMG_20181027_212043_938.jpg"
  etag = "C:/Users/Prat/Desktop/IMG_20181027_212043_938.jpg"
depends_on = [aws_s3_bucket.prattask2terra,
		]
}

locals{
  s3_origin_id = "aws_s3_bucket.prattask2terra.id"
  depends_on = [aws_s3_bucket.prattask2terra,
		]
}


output "test1" {
  value = "aws_security_grp.allow_http_NFS"
  }


resource "aws_instance" "instance_ec2" {
depends_on = [aws_key_pair.terra_task2,
	        aws_security_group.allow_http_NFS,
		]


  ami      = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "terra_task2"
  security_groups = ["allow_http"] 
  tags = {
    Name = "OS1"
  }
 
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terra_pri_task2.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }

provisioner "remote-exec"  {
    inline = [
      "sudo yum install httpd php git -y",                 
      "sudo systemctl start httpd",                  
      "sudo systemctl enable httpd",                   
      
    ]
  }


}

resource "aws_efs_file_system" "allow_nfs" {
 depends_on =  [ aws_security_group.allow_http_NFS,
                aws_instance.instance_ec2,  ] 
  creation_token = "allow_nfs"


  tags = {
    Name = "allow_nfs"
  }
}

resource "aws_efs_mount_target" "mount_target" {
 depends_on =  [ aws_efs_file_system.allow_nfs,
                         ] 
  file_system_id = aws_efs_file_system.allow_nfs.id
  subnet_id      = aws_instance.instance_ec2.subnet_id                         
  security_groups = [aws_security_group.allow_http_NFS.id]
}




resource "null_resource" "null-remote-1"  {
 depends_on = [ 
               aws_efs_mount_target.mount_target,
                  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terra_pri_task2.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
  }
  provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.allow_nfs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.allow_nfs.dns_name}:/  /var/www/html",
        "sudo https://raw.githubusercontent.com/pratiksha1291/new-repo/master/task2.html > index.html",                                 
        "sudo cp index.html  /var/www/html/",                  
      ]
  }
}

resource "aws_cloudfront_origin_access_identity" "o" {
     comment = "this"
 }


resource "aws_cloudfront_distribution" "cloudfront1" {
  depends_on = [ 
                 aws_s3_bucket_object.object,
                  ]


  origin {
    domain_name = aws_s3_bucket.prattask2terra.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
           origin_access_identity = aws_cloudfront_origin_access_identity.o.cloudfront_access_identity_path 
     }
  }

enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  


  logging_config {
    include_cookies = false
    bucket          =  aws_s3_bucket.prattask2terra.bucket_domain_name
    
  }
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id


    forwarded_values {
      query_string = false


      cookies {
        forward = "none"
      }
    }


    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id


    forwarded_values {
      query_string = false
   


      cookies {
        forward = "none"
      }
    }


    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }


  price_class = "PriceClass_200"


  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "IN","CA", "GB", "DE"]
    }
  }


  tags = {
    Environment = "production"
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


output "out3" {
        value = aws_cloudfront_distribution.cloudfront1.domain_name
}

resource "null_resource" "null_resource2" {
 depends_on = [ aws_cloudfront_distribution.cloudfront1, ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terra_pri_task2.private_key_pem
    host     = aws_instance.instance_ec2.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.cloudfront1.domain_name}/${aws_s3_bucket_object.object.key }'>\" >> /var/www/html/index.html",
       "EOF"
   ]
 }
}

resource "null_resource" "null_resource3" {
  depends_on = [
      null_resource.null_resource2,
   ]
   provisioner "local-exec" {
         command = "start chrome ${aws_instance.instance_ec2.public_ip}/index.html"
    }
}

