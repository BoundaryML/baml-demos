import { notFound } from 'next/navigation';
import LaunchStudio from '@/components/launch-studio';
import { demos } from '@/lib/demos';

export function generateStaticParams() {
  return demos.map((demo) => ({ demo: demo.namespace }));
}

export default async function DemoPage({ params }: { params: Promise<{ demo: string }> }) {
  const { demo: namespace } = await params;
  const demo = demos.find((item) => item.namespace === namespace);
  if (!demo) notFound();

  return <LaunchStudio key={demo.id} selected={demo.id} />;
}
