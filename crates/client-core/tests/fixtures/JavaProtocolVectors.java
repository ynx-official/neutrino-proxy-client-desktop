import io.netty.buffer.ByteBuf;
import io.netty.buffer.ByteBufUtil;
import io.netty.buffer.Unpooled;
import io.netty.channel.embedded.EmbeddedChannel;
import org.dromara.neutrinoproxy.core.ProxyMessage;
import org.dromara.neutrinoproxy.core.ProxyMessageDecoder;
import org.dromara.neutrinoproxy.core.ProxyMessageEncoder;
import java.util.Arrays;

// Reproducible fixtures from the unchanged Java implementation (baseline d2b96da6).
// Run with compiled neutrino-proxy-core and its Netty dependencies on the classpath.
class JavaProtocolVectors {
    public static void main(String[] args) {
        ProxyMessage message = new ProxyMessage();
        message.setType((byte) 5);
        message.setSerialNumber(72L);
        message.setInfo("访客");
        message.setData(new byte[] {0, (byte) 255, 31});
        EmbeddedChannel encoder = new EmbeddedChannel(new ProxyMessageEncoder());
        encoder.writeOutbound(message);
        ByteBuf normal = encoder.readOutbound();
        System.out.println("[");
        int[][] settings = {{3,1,0,0}, {2,2,0,0}, {1,3,0,0}, {0,4,0,0}, {0,8,0,8}, {1,2,-3,3}, {1,2,3,3}};
        for (int i = 0; i < settings.length; i++) {
            int[] p = settings[i];
            ByteBuf wire = Unpooled.buffer();
            if (p[1] == 8) wire.writeLong(normal.readableBytes());
            else if (p[3] == 3) wire.writeByte(0xaa).writeShort(normal.readableBytes() - p[2]);
            wire.writeBytes(normal, normal.readerIndex(), normal.readableBytes());
            int max = wire.readableBytes();
            String hex = ByteBufUtil.hexDump(wire);
            EmbeddedChannel decoder = new EmbeddedChannel(new ProxyMessageDecoder(max, p[0], p[1], p[2], p[3]));
            decoder.writeInbound(wire);
            ProxyMessage decoded = decoder.readInbound();
            if (decoded == null || decoded.getType() != 5 || decoded.getSerialNumber() != 72L
                || !decoded.getInfo().equals("访客") || !Arrays.equals(decoded.getData(), message.getData())) {
                throw new AssertionError("Java decode failed for " + Arrays.toString(p));
            }
            decoder.finishAndReleaseAll();
            System.out.printf("  {\"max\":%d,\"offset\":%d,\"width\":%d,\"adjustment\":%d,\"strip\":%d,\"hex\":\"%s\"}%s%n", max,p[0],p[1],p[2],p[3],hex,i+1<settings.length?",":"");
        }
        normal.release();
        encoder.finishAndReleaseAll();
        System.out.println("]");
    }
}
