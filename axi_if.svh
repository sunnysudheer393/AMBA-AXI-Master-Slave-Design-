import axi_pkg::*;

interface axi_if;

    //Global Signals
    logic ACLK;
    logic ARESETn;

    //Low power interface signals
    logic CSYSREQ;
    logic CSYSACK;
    logic CACTIVE;

    //Write Address Channel Signals
    logic [AXI_AWID_WIDTH-1:0] AWID;
    logic [AXI_AWADDR_WIDTH-1:0] AWADDR;
    logic [AXI_AWLEN_WIDTH-1:0] AWLEN;
    logic [AXI_AWSIZE_WIDTH-1:0] AWSIZE;
    logic [AXI_AWBURST_WIDTH-1:0] AWBURST;
    logic [AXI_AWLOCK_WIDTH-1:0] AWLOCK;
    logic [AXI_AWCACHE_WIDTH-1:0] AWCACHE;
    logic [AXI_AWPROT_WIDTH-1:0] AWPROT;
    logic [AXI_AWQOS_WIDTH-1:0] AWQOS;
    logic [AXI_AWREGION_WIDTH-1:0] AWREGION;
    logic [AXI_AWUSER_WIDTH-1:0] AWUSER;
    logic AWVALID;
    logic AWREADY;



    //Write Data Channel Signals
    logic [AXI_WID_WIDTH-1:0] WID;
    logic [AXI_WDATA_WIDTH-1:0] WDATA;
    logic [AXI_WSTRB_WIDTH-1:0] WSTRB;
    logic [AXI_WLAST_WIDTH-1:0] WLAST;
    logic [AXI_WUSER_WIDTH-1:0] WUSER;
    logic WVALID;
    logic WREADY;



    //Write Response Channel Signals
    logic [AXI_BID_WIDTH-1:0] BID;
    logic [AXI_BRESP_WIDTH-1:0] BRESP;
    logic [AXI_BUSER_WIDTH-1:0] BUSER;
    logic BVALID;
    logic BREADY;



    //Read Address Channel Signals
    logic [AXI_ARID_WIDTH-1:0] ARID;
    logic [AXI_ARADDR_WIDTH-1:0] ARADDR;
    logic [AXI_ARLEN_WIDTH-1:0] ARLEN;
    logic [AXI_ARSIZE_WIDTH-1:0] ARSIZE;
    logic [AXI_ARBURST_WIDTH-1:0] ARBURST;
    logic [AXI_ARLOCK_WIDTH-1:0] ARLOCK;
    logic [AXI_ACACHE_WIDTH-1:0] ACACHE;
    logic [AXI_ARPROT_WIDTH-1:0] ARPROT;
    logic [AXI_ARQOS_WIDTH-1:0] ARQOS;
    logic [AXI_ARREGION_WIDTH-1:0] ARREGION;
    logic [AXI_ARUSER_WIDTH-1:0] ARUSER;
    logic ARVALID;
    logic ARREADY;



    //Read Data Channel Signals
    logic [AXI_RID_WIDTH-1:0] RID;
    logic [AXI_RDATA_WIDTH-1:0] RDATA;
    logic [AXI_RRESP_WIDTH-1:0] RRESP;
    logic [AXI_RLAST_WIDTH-1:0] RLAST;
    logic [AXI_RUSER_WIDTH-1:0] RUSER;
    logic RVALID;
    logic RREADY;




endinterface
