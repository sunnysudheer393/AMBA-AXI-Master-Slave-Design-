package axi_pkg;
    
    
    localparam int AXI_AWID_WIDTH = 4; // 4 bits for ID (0-15)
    localparam int AXI_AWADDR_WIDTH = 32; // 32 bits for address bus
    localparam int AXI_AWLEN_WIDTH = 4; // 4 bits for burst length (0-15)
    localparam int AXI_AWSIZE_WIDTH = 3; // 3 bits for burst size (0-7)
    localparam int AXI_AWBURST_WIDTH = 3; // 3 bits for burst type (0-7)
    localparam int AXI_AWLOCK_WIDTH = 2; // 2 bits for lock type (0-3)
    localparam int AXI_AWCACHE_WIDTH = 4; // 4 bits for cache type (0-15)
    localparam int AXI_AWPROT_WIDTH = 3; // 3 bits for protection type (0-7)
    localparam int AXI_AWQOS_WIDTH = 4; // 4 bits for quality of service (0-15)
    localparam int AXI_AWREGION_WIDTH = 4; // 4 bits for region (0-15)
    localparam int AXI_AWUSER_WIDTH = 1; // 1 bit for user-defined signals (0-1)


    localparam int AXI_WID_WIDTH = 4; // 4 bits for write ID (0-15)
    localparam int AXI_WDATA_WIDTH = 32; // 32 bits for write data bus
    localparam int AXI_WSTRB_WIDTH = 4; // 4 bits for write strobe (0-15)
    localparam int AXI_WLAST_WIDTH = 1; // 1 bit for write last signal (0-1)
    localparam int AXI_WUSER_WIDTH = 1; // 1 bit for user-defined signals (0-1)


    localparam int AXI_BID_WIDTH = 4; // 4 bits for write response ID (0-15)
    localparam int AXI_BRESP_WIDTH = 2; // 2 bits for write
    localparam int AXI_BUSER_WIDTH = 1; // 1 bit for user-defined signals (0-1)



    localparam int AXI_ARID_WIDTH = 4; // 4 bits for ID (0-15)
    localparam int AXI_ARADDR_WIDTH = 32; // 32 bits for address bus
    localparam int AXI_ARLEN_WIDTH = 4; // 4 bits for burst length (0-15)
    localparam int AXI_ARSIZE_WIDTH = 3; // 3 bits for burst size (0-7)
    localparam int AXI_ARBURST_WIDTH = 3; // 3 bits for burst type (0-7)
    localparam int AXI_ARLOCK_WIDTH = 2; // 2 bits for lock type (0-3)
    localparam int AXI_ACACHE_WIDTH = 4; // 4 bits for cache type (0-15)
    localparam int AXI_ARPROT_WIDTH = 3; // 3 bits for protection type (0-7)
    localparam int AXI_ARQOS_WIDTH = 4; // 4 bits for quality of service (0-15)
    localparam int AXI_ARREGION_WIDTH = 4; // 4 bits for region (0-15)
    localparam int AXI_ARUSER_WIDTH = 1; // 1 bit for user-defined signals (0-1)


    localparam int AXI_RID_WIDTH = 4; // 4 bits for read ID (0-15)
    localparam int AXI_RDATA_WIDTH = 32; // 32 bits for read data bus
    localparam int AXI_RRESP_WIDTH = 2; // 2 bits for read response (0-3)
    localparam int AXI_RLAST_WIDTH = 1; // 1 bit for read last signal (0-1)
    localparam int AXI_RUSER_WIDTH = 1; // 1 bit for user-defined signals (0-1)
    

endpackage
