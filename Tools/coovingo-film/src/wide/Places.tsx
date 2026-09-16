import { Canvas, Phone } from "./design";
export const Places = () => (
  <Canvas dark bg="bg-london.jpg">
    <div
      style={{
        position: "absolute",
        left: 110,
        top: 70,
        fontSize: 68,
        fontWeight: 500,
      }}
    >
      换个场景，也换个话题。
    </div>
    <div
      style={{
        position: "absolute",
        right: 110,
        top: 87,
        fontSize: 30,
        opacity: 0.8,
      }}
    >
      城市活动，让开口有个由头。
    </div>
    {["park", "pond", "raincafe"].map((n, i) => (
      <Phone
        key={n}
        file={`activity-${n}-wide.png`}
        x={365 + i * 465}
        y={210}
        w={320}
        angle={0}
        delay={10 + i * 14}
      />
    ))}
    <div
      style={{
        position: "absolute",
        left: 365,
        right: 300,
        top: 940,
        display: "flex",
        gap: 145,
        fontSize: 29,
      }}
    >
      {["公园 · 问问路线", "池畔 · 聊聊速写", "雨天 · 聊聊生活"].map((s) => (
        <div key={s} style={{ width: 320, textAlign: "center" }}>
          {s}
        </div>
      ))}
    </div>
  </Canvas>
);
