import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Easing,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";

export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;
export const media = (name: string) => staticFile(`media/${name}`);
export const ink = "#192f41";

export const Paper: React.FC<{ children: React.ReactNode; tone?: string }> = ({
  children,
  tone = "#f5f2e9",
}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill
      style={
        {
          backgroundColor: tone,
          color: ink,
          overflow: "hidden",
          "--paper": tone,
        } as React.CSSProperties
      }
    >
      <Interactive.Div
        name="Soft daylight"
        style={{
          position: "absolute",
          left: -380,
          top: 380,
          width: 1300,
          height: 1300,
          borderRadius: "50%",
          background: "radial-gradient(circle, #bddce16b, transparent 68%)",
          translate: interpolate(frame, [0, 450], ["0px 0px", "110px -80px"], {
            ...clamp,
            easing: ease,
          }),
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 70,
          right: 70,
          top: 100,
          borderTop: "1px solid #18354b26",
        }}
      />
      {children}
    </AbsoluteFill>
  );
};

export const Eyebrow: React.FC<{
  children: React.ReactNode;
  light?: boolean;
}> = ({ children, light }) => (
  <Interactive.Div
    name="Chapter label"
    style={{
      position: "absolute",
      left: 86,
      top: 126,
      fontSize: 24,
      fontWeight: 600,
      letterSpacing: 3,
      color: light ? "#e9d5b1" : "#567285",
    }}
  >
    {children}
  </Interactive.Div>
);

export const Title: React.FC<{
  children: React.ReactNode;
  light?: boolean;
  size?: number;
  top?: number;
}> = ({ children, light, size = 92, top = 202 }) => {
  const frame = useCurrentFrame();
  return (
    <Interactive.Div
      name="Editorial headline"
      style={{
        position: "absolute",
        left: 82,
        right: 75,
        top,
        fontSize: size,
        fontWeight: 600,
        letterSpacing: -3,
        lineHeight: 1.2,
        color: light ? "#faf5e9" : ink,
        opacity: interpolate(frame, [8, 42], [0, 1], { ...clamp }),
        translate: interpolate(frame, [8, 64], ["0px 46px", "0px 0px"], {
          ...clamp,
          easing: ease,
        }),
      }}
    >
      {children}
    </Interactive.Div>
  );
};

export const Note: React.FC<{
  children: React.ReactNode;
  top?: number;
  light?: boolean;
}> = ({ children, top = 448, light }) => {
  const frame = useCurrentFrame();
  return (
    <Interactive.Div
      name="Supporting copy"
      style={{
        position: "absolute",
        left: 86,
        right: 80,
        top,
        fontSize: 44,
        lineHeight: 1.5,
        color: light ? "#d3dfdf" : "#526774",
        opacity: interpolate(frame, [35, 67], [0, 1], clamp),
        translate: interpolate(frame, [35, 80], ["0px 18px", "0px 0px"], {
          ...clamp,
          easing: ease,
        }),
      }}
    >
      {children}
    </Interactive.Div>
  );
};

export const Foot: React.FC<{ children: React.ReactNode; light?: boolean }> = ({
  children,
  light,
}) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      right: 0,
      bottom: 0,
      height: 220,
      background: "linear-gradient(transparent, var(--paper) 42%)",
    }}
  >
    <div
      style={{
        position: "absolute",
        left: 86,
        right: 86,
        bottom: 100,
        fontSize: 26,
        lineHeight: 1.5,
        color: light ? "#dae3e5" : "#526774",
        display: "flex",
        justifyContent: "space-between",
      }}
    >
      <span>{children}</span>
      <span style={{ letterSpacing: 2 }}>COOVINGO</span>
    </div>
  </div>
);

export const Screen: React.FC<{
  file: string;
  x: number;
  y: number;
  w: number;
  angle?: number;
  delay?: number;
}> = ({ file, x, y, w, angle = 0, delay = 30 }) => {
  const frame = useCurrentFrame();
  return (
    <Interactive.Div
      name="Native iPhone screenshot"
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        borderRadius: 52,
        padding: 9,
        background: "#172c36",
        boxShadow: "0 36px 70px #163b452b, inset 0 0 0 2px #6c7d85",
        rotate: `${angle}deg`,
        opacity: interpolate(frame, [delay, delay + 30], [0, 1], clamp),
        translate: interpolate(
          frame,
          [delay, delay + 75],
          ["0px 100px", "0px 0px"],
          { ...clamp, easing: ease },
        ),
      }}
    >
      <div style={{ borderRadius: 43, overflow: "hidden" }}>
        <CanvasImage
          src={media(file)}
          style={{ width: "100%", display: "block" }}
        />
      </div>
    </Interactive.Div>
  );
};

// An editorial close-up of untouched native pixels, not reconstructed app controls.
export const Detail: React.FC<{
  file: string;
  top: number;
  height: number;
  crop: number;
  width?: number;
  left?: number;
  delay?: number;
}> = ({ file, top, height, crop, width = 908, left = 86, delay = 45 }) => {
  const frame = useCurrentFrame();
  return (
    <Interactive.Div
      name="Native detail crop"
      style={{
        position: "absolute",
        left,
        top,
        width,
        height,
        borderRadius: 38,
        overflow: "hidden",
        background: "#f5f7f7",
        boxShadow: "0 25px 70px #173d4824",
        opacity: interpolate(frame, [delay, delay + 30], [0, 1], clamp),
        translate: interpolate(
          frame,
          [delay, delay + 65],
          ["0px 60px", "0px 0px"],
          { ...clamp, easing: ease },
        ),
      }}
    >
      <CanvasImage
        src={media(file)}
        style={{ position: "absolute", width, top: (-crop * width) / 1170 }}
      />
    </Interactive.Div>
  );
};
