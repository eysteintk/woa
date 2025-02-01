// app/components/ui/EChartsViz.tsx
'use client';

import React from 'react';
import ReactEChartsCore from 'echarts-for-react/lib/core';
import * as echarts from 'echarts/core';
import { ScatterChart, LineChart, BarChart, MapChart, GraphChart } from 'echarts/charts';
import { TitleComponent, TooltipComponent, LegendComponent, GeoComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

echarts.use([ScatterChart, LineChart, BarChart, MapChart, GraphChart, TitleComponent, TooltipComponent, LegendComponent, GeoComponent, CanvasRenderer]);

interface EChartsVizProps {
  option: any;
  style?: React.CSSProperties;
  onEvents?: { [key: string]: (params:any)=>void };
}

export function EChartsViz({ option, style, onEvents }: EChartsVizProps) {
  return (
    <ReactEChartsCore
      echarts={echarts}
      option={option}
      style={style || { width: '100%', height: '400px' }}
      notMerge={false}
      lazyUpdate={true}
      onEvents={onEvents}
    />
  );
}
