//
//  FCReborn-Bridging-Header.h
//  FCReborn
//
//  Swift の Darwin モジュールでは自動 import されない低レベル C ヘッダを
//  Swift から使えるようにするための Bridging Header。
//
//  用途: WiFiHelper.swift で sysctl(PF_ROUTE) を叩いて default gateway を
//  取得するのに、rt_msghdr / RTF_GATEWAY / RTA_DST 等の定義が必要。
//

#ifndef FCReborn_Bridging_Header_h
#define FCReborn_Bridging_Header_h

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#endif /* FCReborn_Bridging_Header_h */
