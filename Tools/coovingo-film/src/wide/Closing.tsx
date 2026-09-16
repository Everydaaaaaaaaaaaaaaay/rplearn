import { Canvas, Phone } from "./design";
import { CanvasImage } from "remotion";
import { media } from "../design";
export const Closing = () => (
  <Canvas dark bg="bg-london.jpg">
    <div style={{ position: "absolute", left: 160, top: 220, width: 780 }}>
      <CanvasImage
        src={media("icon.png")}
        style={{ width: 140, height: 140, borderRadius: 32 }}
      />
      <div style={{ fontSize: 49, marginTop: 32 }}>
        咕游记{" "}
        <span
          style={{
            fontSize: 25,
            letterSpacing: 5,
            opacity: 0.6,
            marginLeft: 18,
          }}
        >
          COOVINGO
        </span>
      </div>
      <div style={{ fontSize: 83, marginTop: 50, fontWeight: 500 }}>
        边聊边学，没压力
      </div>
    </div>
    <Phone file="02-chat.png" x={1210} y={110} w={360} angle={-5} />
    <Phone file="03-dictionary.png" x={1505} y={200} w={305} angle={6} />
    <div
      style={{
        position: "absolute",
        left: 160,
        bottom: 80,
        fontSize: 19,
        lineHeight: 1.6,
        opacity: 0.64,
      }}
    >
      原生实机与模拟器演示 · AI 虚构角色
      <br />
      Music: George Street Shuffle — Kevin MacLeod · incompetech.com
      <br />
      CC BY 4.0 · Edited excerpt · creativecommons.org/licenses/by/4.0/
    </div>
  </Canvas>
);
