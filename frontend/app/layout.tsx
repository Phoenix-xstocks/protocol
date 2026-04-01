import type { Metadata } from 'next';
import { Web3Provider } from '@/providers/Web3Provider';
import { Navbar } from '@/components/layout/Navbar';
import { Footer } from '@/components/layout/Footer';
import { Toaster } from 'sonner';
import './globals.css';

export const metadata: Metadata = {
  title: 'xYield Protocol',
  description: 'Permissionless Autocall on Tokenized Equities',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen flex flex-col antialiased">
        <Web3Provider>
          <Navbar />
          {children}
          <Footer />
          <Toaster
            theme="dark"
            position="bottom-right"
            toastOptions={{
              style: {
                background: '#111827',
                border: '1px solid #374151',
                color: '#e5e7eb',
              },
            }}
          />
        </Web3Provider>
      </body>
    </html>
  );
}
